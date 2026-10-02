#!/bin/sh
# aichat.boxes.library.sh
#
# The AgentVM Boxes window (Tools > AgentVM Boxes, aichat.boxes.json): the boxes on this Mac and
# their states, with Start, Stop and View for the selected one. That is all Cadabra does to a box
# outside a conversation: making, changing and deleting boxes, images, and installing or updating
# agent-vm belong to the AgentVM app, which the window's Open AgentVM button opens (at the
# selected box, when one is selected). Everything that talks to agent-vm goes through
# aichat.agentvm.library.sh; this file only turns its rows into the window.
#
# STATE. Handlers overlap and their environment is a snapshot taken at dispatch, so each one acts
# on the box selected when it was dispatched, and what must outlive a handler lives outside it:
#   - the rows last read from `agent-vm status`, in cache files of the window (boxes, jobs, vms,
#     and the list as last painted);
#   - on the pasteboard, per window: the selected box, the jobs this window started (so a start
#     that fails is reported once, here), and the token of the one poll loop allowed to run;
#   - globally, the uuid of the open window, so Tools > AgentVM Boxes brings it to the front.
#
# THE POLL LOOP (aichat.boxes.poll) runs while the window is open, since boxes change from
# elsewhere: a conversation starts one, the AgentVM app or Terminal stops one. `status` takes a
# few hundredths of a second. Each start of the loop takes over by writing its own token; an
# older loop sees another token and exits, and closing the window writes "closed".
[ -n "${__AICHAT_BOXES_LIB:-}" ] && return 0
__AICHAT_BOXES_LIB=1

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh"

BOXES_STATUS_ID=100
BOXES_REFRESH_ID=120
BOXES_APP_ID=130
BOXES_LIST_ID=300
BOXES_START_ID=551
BOXES_STOP_ID=552
BOXES_VIEW_ID=553

# The open window's uuid, for Tools > AgentVM Boxes. Keyed by this process, so a uuid left behind
# by a Cadabra that quit or crashed with the window open is never read.
BOXES_WINDOW_KEY="cadabra_boxes_window_${OMC_APP_PROCESS_ID}"

# Seconds between two readings: while a job works on a box, and otherwise. CADABRA_BOXES_POLL_BUSY
# and _IDLE are test seams, and CADABRA_BOXES_POLL_PASSES ends the loop after that many readings.
boxes_poll_busy="${CADABRA_BOXES_POLL_BUSY:-1}"
boxes_poll_idle="${CADABRA_BOXES_POLL_IDLE:-4}"

# -- Small helpers ---------------------------------------------------------------------------

boxes_key() { printf '%s_%s\n' "$1" "$2"; }

# boxes_cache <uuid> <boxes|jobs|vms|cards>  ->  the file holding the rows last read or painted.
boxes_cache() {
    cadabra_run_file "boxes.$1.$2"
}

boxes_enable() {
    if [ "$3" = "1" ]; then
        "$dialog" "$1" "$2" omc_enable
    else
        "$dialog" "$1" "$2" omc_disable
    fi
}

# boxes_store <file>  ->  stdin's non-empty lines become the cache file, replaced in one step:
# other handlers read the caches while the poll loop rewrites them, and a file truncated for
# rewriting reads as "no such box".
boxes_store() {
    /usr/bin/awk 'NF' > "$1.$$"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        /bin/rm -f "$1.$$"
        return "$_status"
    fi
    /bin/mv -f "$1.$$" "$1"
}

# boxes_row <uuid> <name>  ->  the cached row of that box (agentvm_status_box_rows).
boxes_row() {
    local _file="$(boxes_cache "$1" boxes)"
    [ -f "$_file" ] || return 0
    /usr/bin/awk -F'\t' -v name="$2" '$1 == name { print; exit }' "$_file"
}

# boxes_field <row> <n>  ->  field n of a row, "" for "-".
boxes_field() {
    local _value="$(printf '%s\n' "$1" | /usr/bin/cut -f"$2")"
    [ "$_value" = "-" ] && _value=""
    printf '%s\n' "$_value"
}

# boxes_alert_error <title> <status>  ->  agent-vm's message (or the library's) in an alert.
boxes_alert_error() {
    local _message="$(agentvm_last_error "$2")"
    "$alert" --level stop --title "$1" "$_message"
}

# boxes_selected <uuid>  ->  the selected box's name, or nothing.
boxes_selected() {
    "$pasteboard" "$(boxes_key cadabra_boxes_selected "$1")" get
}

# -- Reading -----------------------------------------------------------------------------------

# boxes_unusable_text <agentvm_available's status> <its reason>  ->  the one line the window
# shows when boxes cannot be used; the whole reason is the line's tooltip.
boxes_unusable_text() {
    case "$1" in
        "$agentvm_not_installed") echo "AgentVM is not set up on this Mac. Open AgentVM to set it up." ;;
        "$agentvm_too_old")       echo "AgentVM on this Mac needs an update. Open AgentVM to update it." ;;
        *)                        printf '%s\n' "$2" ;;
    esac
}

# boxes_read <uuid>  ->  0 once the caches hold what `agent-vm status` says now. Otherwise the
# reason is left in the cache "problem" (line 1: what the window shows; line 2: the whole reason;
# line 3: "macos" when this Mac's macOS is too old for boxes and for the AgentVM app alike), and
# it returns 1. The caches are emptied when boxes cannot be used at all, and kept as last read
# when only this `status` failed.
boxes_read() {
    local _uuid="$1"
    local _problem="$(boxes_cache "$_uuid" problem)"
    local _reason
    _reason="$(agentvm_available)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        local _macos=""
        [ -n "$(agentvm_macos_reason "$(/usr/bin/sw_vers -productVersion 2>/dev/null)")" ] && _macos="macos"
        printf '%s\n%s\n%s\n' "$(boxes_unusable_text "$_status" "$_reason")" "$_reason" "$_macos" > "$_problem"
        : | boxes_store "$(boxes_cache "$_uuid" boxes)"
        : | boxes_store "$(boxes_cache "$_uuid" jobs)"
        : | boxes_store "$(boxes_cache "$_uuid" vms)"
        return 1
    fi
    local _json
    _json="$(agentvm_status)"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        _reason="$(agentvm_last_error "$_status" | /usr/bin/tr '\n' ' ')"
        printf '%s\n%s\n\n' "The boxes could not be read." "$_reason" > "$_problem"
        return 1
    fi
    /bin/rm -f "$_problem"
    printf '%s\n' "$_json" | agentvm_status_box_rows | boxes_store "$(boxes_cache "$_uuid" boxes)"
    printf '%s\n' "$_json" | agentvm_status_job_rows | boxes_store "$(boxes_cache "$_uuid" jobs)"
    printf '%s\n' "$_json" | agentvm_status_vm_row | boxes_store "$(boxes_cache "$_uuid" vms)"
    return 0
}

# boxes_held <uuid> <name>  ->  what a job is doing to the box (Starting, Stopping, Busy, or
# Waiting for a job queued behind another), or nothing when no job holds it. A job that runs
# wins over one that waits.
boxes_held() {
    local _file="$(boxes_cache "$1" jobs)"
    [ -f "$_file" ] || return 0
    /usr/bin/awk -F'\t' -v target="box:$2" '
        $3 != target { next }
        $2 == "queued" && held == "" { held = "Waiting" }
        $2 == "running" { held = ($4 == "box start") ? "Starting" : ($4 == "box stop") ? "Stopping" : "Busy" }
        END { if (held != "") print held }' "$_file"
}

# boxes_moving <uuid>  ->  0 while a job works on a box or waits to, or a box is between states.
boxes_moving() {
    local _jobs="$(boxes_cache "$1" jobs)" _boxes="$(boxes_cache "$1" boxes)"
    [ -f "$_jobs" ] || return 1
    local _count="$(/usr/bin/awk -F'\t' '
        FILENAME == jobs && ($2 == "running" || $2 == "queued") && $3 ~ /^box:/ { n++ }
        FILENAME != jobs && ($2 == "starting" || $2 == "stopping") { n++ }
        END { print n + 0 }' jobs="$_jobs" "$_jobs" "$_boxes" 2>/dev/null)"
    [ "${_count:-0}" -gt 0 ]
}

# -- Painting ----------------------------------------------------------------------------------

# boxes_card_rows <uuid>  ->  the list's rows, one per box:
#   1 name   2 the state's symbol   3 the state in words, the image and the memory
#   4 the symbol's color
# A box a job holds looks as a box between states does, and its line begins with what the job
# does.
boxes_card_rows() {
    local _boxes="$(boxes_cache "$1" boxes)" _jobs="$(boxes_cache "$1" jobs)"
    [ -f "$_boxes" ] || return 0
    [ -f "$_jobs" ] || _jobs=/dev/null
    /usr/bin/awk -F'\t' -v jobs="$_jobs" '
        BEGIN {
            while ((getline line < jobs) > 0) {
                split(line, job, "\t")
                if (job[3] !~ /^box:/) continue
                name = substr(job[3], 5)
                if (job[2] == "queued" && !(name in held)) held[name] = "Waiting"
                if (job[2] == "running")
                    held[name] = (job[4] == "box start") ? "Starting" : (job[4] == "box stop") ? "Stopping" : "Busy"
            }
        }
        {
            symbol = "questionmark.circle"; color = "#8E8E93"; words = $2
            if ($2 == "running")           { symbol = "play.circle.fill"; color = "#2E9E4F"; words = "Running" }
            else if ($2 == "stopped")      { symbol = "stop.circle"; words = "Stopped" }
            else if ($2 == "starting")     { symbol = "circle.dotted"; color = "#0A84FF"; words = "Starting" }
            else if ($2 == "stopping")     { symbol = "circle.dotted"; color = "#0A84FF"; words = "Stopping" }
            else if ($2 == "unresponsive") { symbol = "exclamationmark.circle.fill"; color = "#E8861A"; words = "Not responding" }
            if ($1 in held) { symbol = "circle.dotted"; color = "#0A84FF"; words = held[$1] }
            if ($2 == "running" && !($1 in held) && $5 ~ /^[0-9]+$/ && $5 > 0)
                words = words ", " $5 ($5 == 1 ? " program" : " programs")
            caption = words " - " $3
            if ($4 != "-") caption = caption ", " $4 " GB"
            if ($7 == "true") caption = caption ", disposable"
            printf "%s\t%s\t%s\t%s\n", $1, symbol, caption, color
        }' "$_boxes"
}

# boxes_status_text <uuid>  ->  the window's one line when boxes can be used.
boxes_status_text() {
    local _boxes="$(boxes_cache "$1" boxes)"
    local _count=0
    [ -f "$_boxes" ] && _count="$(/usr/bin/awk 'NF { n++ } END { print n + 0 }' "$_boxes")"
    if [ "$_count" -eq 0 ]; then
        echo "No boxes yet. Open AgentVM to make one."
        return 0
    fi
    local _vms="$(/bin/cat "$(boxes_cache "$1" vms)" 2>/dev/null)"
    local _running="$(boxes_field "$_vms" 1)" _limit="$(boxes_field "$_vms" 2)"
    if [ -z "$_running" ] || [ -z "$_limit" ]; then
        echo ""
        return 0
    fi
    printf 'Virtual machines running on this Mac: %s of %s\n' "$_running" "$_limit"
}

# boxes_paint_buttons <uuid>  ->  Start, Stop and View for the selected box, as its state allows.
# A box a job holds takes no button until the job is done.
boxes_paint_buttons() {
    local _uuid="$1"
    local _name="$(boxes_selected "$_uuid")"
    local _row=""
    [ -n "$_name" ] && _row="$(boxes_row "$_uuid" "$_name")"
    local _start=0 _stop=0 _view=0
    if [ -n "$_row" ]; then
        local _state="$(boxes_field "$_row" 2)"
        local _held="$(boxes_held "$_uuid" "$_name")"
        if [ -z "$_held" ]; then
            [ "$_state" = "stopped" ] && _start=1
            [ "$_state" != "stopped" ] && _stop=1
        fi
        [ "$_state" = "running" ] && _view=1
    fi
    boxes_enable "$_uuid" "$BOXES_START_ID" "$_start"
    boxes_enable "$_uuid" "$BOXES_STOP_ID" "$_stop"
    boxes_enable "$_uuid" "$BOXES_VIEW_ID" "$_view"
}

# boxes_paint <uuid>  ->  the window from the caches. The list is set again only when its rows
# changed since they were last painted: a list set again loses its scroll position, and a poll
# loop that changed nothing must not be seen. A selected box that is gone is deselected.
boxes_paint() {
    local _uuid="$1"
    local _problem="$(boxes_cache "$_uuid" problem)"
    local _line="" _help="" _macos=""
    if [ -f "$_problem" ]; then
        _line="$(/usr/bin/sed -n 1p "$_problem")"
        _help="$(/usr/bin/sed -n 2p "$_problem")"
        _macos="$(/usr/bin/sed -n 3p "$_problem")"
    else
        _line="$(boxes_status_text "$_uuid")"
    fi
    "$dialog" "$_uuid" "$BOXES_STATUS_ID" "$_line"
    "$dialog" "$_uuid" "$BOXES_STATUS_ID" omc_set_property help "$_help"
    # The AgentVM app needs the same macOS as boxes do, so on an older one it would not open.
    boxes_enable "$_uuid" "$BOXES_APP_ID" "$([ "$_macos" = "macos" ] && echo 0 || echo 1)"
    local _cards="$(boxes_cache "$_uuid" cards)"
    local _rows="$(boxes_card_rows "$_uuid")"
    local _painted=""
    [ -f "$_cards" ] && _painted="$(/bin/cat "$_cards")"
    if [ ! -f "$_cards" ] || [ "$_rows" != "$_painted" ]; then
        printf '%s\n' "$_rows" | /usr/bin/awk 'NF' | "$dialog" "$_uuid" "$BOXES_LIST_ID" omc_table_set_rows_from_stdin
        printf '%s\n' "$_rows" > "$_cards"
        local _name="$(boxes_selected "$_uuid")"
        if [ -n "$_name" ]; then
            if [ -n "$(boxes_row "$_uuid" "$_name")" ]; then
                # The verb fires no action.
                "$dialog" "$_uuid" "$BOXES_LIST_ID" omc_select_row_with_content "$_name" 1
            else
                "$pasteboard" "$(boxes_key cadabra_boxes_selected "$_uuid")" set ""
            fi
        fi
    fi
    boxes_paint_buttons "$_uuid"
}

# -- Jobs this window started --------------------------------------------------------------------

# boxes_no_slot_text: what a start that agent-vm refused for want of a virtual machine slot says,
# in place of agent-vm's own words, which point to a Terminal command.
boxes_no_slot_text="No virtual machine slot was free: macOS runs at most two macOS virtual machines at once, and that many were running. Stop a box, or a virtual machine in another application, then try again."

# boxes_watched <uuid>  ->  the ids of the jobs this window started and still follows.
boxes_watched() {
    "$pasteboard" "$(boxes_key cadabra_boxes_watch "$1")" get
}

# boxes_note_jobs <uuid> <watched>  ->  the jobs this window started that have ended are
# forgotten, and one that failed is told in an alert, once: the start or stop went on in the
# background, so nothing else would say that it did not work. A canceled job (canceled from the
# AgentVM app or Terminal) is somebody's decision and is not reported. A job `status` no longer
# lists ended more than an hour ago and is forgotten too.
# <watched> is the watch list as it was BEFORE the status in the cache was read (boxes_refresh):
# every job in it existed when agent-vm answered. A job that Start or Stop adds while a reading
# is under way is in the list now but not in that answer, and judged by it would be forgotten
# as long gone, with its failure never told. So only the jobs of <watched> are judged, and only
# those that ended are taken off the list as it is now, which keeps what was added meanwhile.
boxes_note_jobs() {
    local _uuid="$1" _watched="${2:-}"
    case "$_watched" in
        *[!\ ]*) ;;
        *) return 0 ;;
    esac
    local _jobs="$(boxes_cache "$_uuid" jobs)"
    [ -f "$_jobs" ] || return 0
    local _id _row _state _ended="" _failed=""
    # The ids are agent-vm job ids, so word splitting is safe.
    for _id in $_watched; do
        _row="$(/usr/bin/awk -F'\t' -v id="$_id" '$1 == id { print; exit }' "$_jobs")"
        _state="$(boxes_field "$_row" 2)"
        case "$_state" in
            queued|running) ;;
            failed|lost)    _ended="$_ended $_id"; _failed="$_failed $_id" ;;
            *)              _ended="$_ended $_id" ;;
        esac
    done
    [ -n "$_ended" ] || return 0
    # Forgotten before any alert: an alert waits for its answer, and a job must be told once.
    # A failed job that is no longer on the list was taken off by another reading (the poll loop
    # and a handler overlap), which tells it.
    local _key="$(boxes_key cadabra_boxes_watch "$_uuid")"
    local _now="$(boxes_watched "$_uuid")"
    local _left="" _mine=""
    for _id in $_now; do
        case " $_ended " in
            *" $_id "*) ;;
            *) _left="$_left $_id"
               continue ;;
        esac
        case " $_failed " in
            *" $_id "*) _mine="$_mine $_id" ;;
        esac
    done
    "$pasteboard" "$_key" set "$_left"
    local _what _name _title _text
    for _id in $_mine; do
        _row="$(/usr/bin/awk -F'\t' -v id="$_id" '$1 == id { print; exit }' "$_jobs")"
        _what="$(boxes_field "$_row" 4)"
        _name="$(boxes_field "$_row" 3)"
        _name="${_name#box:}"
        _title="Could not start $_name"
        [ "$_what" = "box stop" ] && _title="Could not stop $_name"
        _text="$(boxes_field "$_row" 6)"
        if [ "$(boxes_field "$_row" 5)" = "$agentvm_no_slot_status" ]; then
            _text="$boxes_no_slot_text"
        fi
        "$alert" --level stop --title "$_title" "${_text:-agent-vm gave no reason.}"
    done
}

# boxes_refresh <uuid>  ->  reads, paints and reports. The watch list is taken before the
# reading (see boxes_note_jobs), and a reading that failed says nothing about any job.
boxes_refresh() {
    local _watched="$(boxes_watched "$1")"
    boxes_read "$1"
    local _read=$?
    boxes_paint "$1"
    if [ "$_read" -eq 0 ]; then
        boxes_note_jobs "$1" "$_watched"
    fi
}

# boxes_after_job_start <uuid> <job id>  ->  the job is watched and the window shows it at once.
boxes_after_job_start() {
    local _key="$(boxes_key cadabra_boxes_watch "$1")"
    "$pasteboard" "$_key" set "$("$pasteboard" "$_key" get) $2"
    boxes_read "$1"
    boxes_paint "$1"
    boxes_ensure_poll "$1"
}

# -- The poll loop -----------------------------------------------------------------------------

# boxes_ensure_poll <uuid>  ->  starts a poll loop when none runs for the window: no loop holds
# the token, or the one that holds it ("poll-<its pid>") is gone without giving it up.
boxes_ensure_poll() {
    local _holder="$("$pasteboard" "$(boxes_key cadabra_boxes_poll "$1")" get)"
    local _start=0
    case "$_holder" in
        '') _start=1 ;;
        poll-*[!0123456789]*|poll-) ;;
        poll-*)
            kill -0 "${_holder#poll-}" 2>/dev/null
            [ $? -ne 0 ] && _start=1 ;;
    esac
    if [ "$_start" = "1" ]; then
        "$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.boxes.poll"
    fi
}

# boxes_app_alive  ->  0 while the Cadabra that owns the window runs (or OMC gave no pid).
boxes_app_alive() {
    case "${OMC_APP_PROCESS_ID:-}" in
        ''|*[!0123456789]*) return 0 ;;
    esac
    kill -0 "$OMC_APP_PROCESS_ID" 2>/dev/null
}

# boxes_poll <uuid>  ->  reads and repaints until the window closes, a newer loop takes over, or
# Cadabra goes away.
boxes_poll() {
    local _uuid="$1"
    local _key="$(boxes_key cadabra_boxes_poll "$_uuid")"
    local _token="poll-$$"
    # A loop chained by a handler that was still running when the window closed must not take
    # the token over "closed" and poll a window that is gone.
    local _current="$("$pasteboard" "$_key" get)"
    [ "$_current" = "closed" ] && return 0
    "$pasteboard" "$_key" set "$_token"
    local _passes=0
    local _holder _wait
    while boxes_app_alive; do
        _wait="$boxes_poll_idle"
        boxes_moving "$_uuid" && _wait="$boxes_poll_busy"
        # Wait first: whatever chained the loop has just painted.
        /bin/sleep "$_wait"
        _holder="$("$pasteboard" "$_key" get)"
        [ "$_holder" = "$_token" ] || return 0
        boxes_app_alive || break
        boxes_refresh "$_uuid"
        _passes=$((_passes + 1))
        if [ -n "${CADABRA_BOXES_POLL_PASSES:-}" ] && [ "$_passes" -ge "$CADABRA_BOXES_POLL_PASSES" ]; then
            break
        fi
    done
    _holder="$("$pasteboard" "$_key" get)"
    [ "$_holder" = "$_token" ] && "$pasteboard" "$_key" set ""
    return 0
}
