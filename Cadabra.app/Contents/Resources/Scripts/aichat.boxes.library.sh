#!/bin/sh
# aichat.boxes.library.sh
#
# The Box Manager window (Tools > Boxes..., aichat.boxes.json): the agent-vm images and boxes on
# this Mac, what each one is, the jobs that work on them, and the buttons that act on them.
# Everything that talks to agent-vm goes through aichat.agentvm.library.sh; this file only turns
# its rows into the window.
#
# STATE. Handlers overlap and their environment is a snapshot taken at dispatch, so each one
# acts on the row selected when it was dispatched, and the pieces of state that must outlive a
# handler live outside it:
#   - the rows last read from agent-vm, in cache files beside the handler's TMPDIR, so a
#     selection shows an image's details without asking agent-vm again (`image list` costs about
#     0.3 s per derived image);
#   - on the pasteboard, per window: which table is shown, what the detail pane shows (so a
#     finished job can repaint it), and the token of the one poll loop allowed to run;
#   - globally, the uuid of the open Box Manager, so the New Box window can refresh it.
#
# THE POLL LOOP (aichat.boxes.poll) runs only while jobs run: it repaints the jobs table once a
# second and refreshes the lists when a job ends. Each start of it takes over by writing its own
# token; an older loop sees another token and exits, and closing the window writes "closed".
[ -n "${__AICHAT_BOXES_LIB:-}" ] && return 0
__AICHAT_BOXES_LIB=1

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh"

BOXES_HEADER_ID=100
BOXES_NOTES_ID=101
BOXES_KIND_ID=110
BOXES_REFRESH_ID=120
BOXES_NEW_BOX_ID=121
BOXES_IMAGES_ID=200
BOXES_BOXES_ID=300
BOXES_JOBS_ID=400
BOXES_JOB_CANCEL_ID=401
BOXES_JOB_FORGET_ID=402
BOXES_PROGRESS_ID=405
BOXES_TITLE_ID=500
BOXES_SUBTITLE_ID=501
BOXES_DETAIL_ID=510
BOXES_IMAGE_BUTTONS_ID=540
BOXES_IMAGE_NEW_BOX_ID=541
BOXES_IMAGE_UPDATE_ID=542
BOXES_IMAGE_SETUP_ID=543
BOXES_IMAGE_REVEAL_ID=544
BOXES_IMAGE_DELETE_ID=545
BOXES_BOX_BUTTONS_ID=550
BOXES_BOX_START_ID=551
BOXES_BOX_STOP_ID=552
BOXES_BOX_VIEW_ID=553
BOXES_BOX_CONTROL_ID=554
BOXES_BOX_SHELL_ID=555
BOXES_BOX_REVEAL_ID=556
BOXES_BOX_DELETE_ID=557

BOXES_IMAGE_ACTION_IDS="$BOXES_IMAGE_NEW_BOX_ID $BOXES_IMAGE_UPDATE_ID $BOXES_IMAGE_SETUP_ID $BOXES_IMAGE_REVEAL_ID $BOXES_IMAGE_DELETE_ID"
BOXES_BOX_ACTION_IDS="$BOXES_BOX_START_ID $BOXES_BOX_STOP_ID $BOXES_BOX_VIEW_ID $BOXES_BOX_CONTROL_ID $BOXES_BOX_SHELL_ID $BOXES_BOX_REVEAL_ID $BOXES_BOX_DELETE_ID"

# The open Box Manager's window uuid, for Tools > Boxes... and the windows that change what it
# lists. Keyed by this process, so a uuid left behind by a Cadabra that quit or crashed with the
# window open is never read.
BOXES_MANAGER_KEY="cadabra_boxes_manager_window_${OMC_APP_PROCESS_ID}"

# CADABRA_OPEN is the test seam for /usr/bin/open (Reveal), as in aichat.agentvm.library.sh.
boxes_open="${CADABRA_OPEN:-/usr/bin/open}"

boxes_tab="$(printf '\t')"

# -- Small helpers ---------------------------------------------------------------------------

boxes_key() { printf '%s_%s\n' "$1" "$2"; }

# boxes_cache <uuid> <images|boxes|jobs>  ->  the file holding the rows last read.
boxes_cache() {
    printf '%s/cadabra-boxes.%s.%s\n' "${TMPDIR:-/tmp}" "$1" "$2"
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
# rewriting reads as "no such row" (the detail pane clears) or "no job runs" (buttons enable).
boxes_store() {
    /usr/bin/awk 'NF' > "$1.$$"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        /bin/rm -f "$1.$$"
        return "$_status"
    fi
    /bin/mv -f "$1.$$" "$1"
}

# boxes_line <label> <value> [unit]  ->  one aligned detail line, or nothing when the value is
# unknown (agent-vm left the field out).
boxes_line() {
    [ -n "$2" ] || return 0
    printf '%-15s%s%s\n' "$1" "$2" "${3:+ $3}"
}

# boxes_row <file> <name>  ->  the cached row whose first field is name.
boxes_row() {
    [ -f "$1" ] || return 0
    /usr/bin/awk -F'\t' -v name="$2" '$1 == name { print; exit }' "$1"
}

# boxes_field <row> <n>  ->  field n of a row, "" for "-".
boxes_field() {
    local _value="$(printf '%s\n' "$1" | /usr/bin/cut -f"$2")"
    [ "$_value" = "-" ] && _value=""
    printf '%s\n' "$_value"
}

# boxes_busy_word <kind>  ->  what a running job of that kind is doing, for the State column.
boxes_busy_word() {
    case "$1" in
        box-start)    echo "starting..." ;;
        box-stop)     echo "stopping..." ;;
        update-guest) echo "updating..." ;;
        image-setup)  echo "setting up..." ;;
        image-create) echo "building..." ;;
        *)            echo "busy..." ;;
    esac
}

# boxes_alert_error <title> <status>  ->  agent-vm's message (or the library's) in an alert.
boxes_alert_error() {
    local _message="$(agentvm_last_error "$2")"
    "$alert" --level stop --title "$1" "$_message"
}

# -- The header ------------------------------------------------------------------------------

# boxes_show_header <uuid>  ->  0 when agent-vm can be used; otherwise the header says why, the
# controls are disabled, and it returns 1.
boxes_show_header() {
    local _uuid="$1"
    local _reason
    _reason="$(agentvm_available)"
    if [ $? -ne 0 ]; then
        "$dialog" "$_uuid" "$BOXES_HEADER_ID" "Boxes are not available"
        "$dialog" "$_uuid" "$BOXES_NOTES_ID" "$_reason"
        local _id
        for _id in $BOXES_KIND_ID $BOXES_REFRESH_ID $BOXES_NEW_BOX_ID $BOXES_HEADER_NEW_IMAGE_ID; do
            "$dialog" "$_uuid" "$_id" omc_disable
        done
        return 1
    fi
    local _version="$(agentvm_version_info | /usr/bin/cut -f1)"
    local _origin="$(agentvm_origin)"
    local _where="the one inside Cadabra"
    case "$_origin" in
        developer) _where="developer build: $(agentvm_bin)" ;;
        test)      _where="test double" ;;
    esac
    "$dialog" "$_uuid" "$BOXES_HEADER_ID" "agent-vm ${_version:-?} ($_where)"
    # Doctor's warnings and failures, as it words them: a full set of VM slots, low disk space,
    # a signature that will not run elsewhere.
    local _notes="$(agentvm_doctor | /usr/bin/awk -F'\t' '$2 == "warning" || $2 == "failure" { printf "%s%s: %s", sep, $1, $3; sep = "\n" }')"
    "$dialog" "$_uuid" "$BOXES_NOTES_ID" "$_notes"
    return 0
}

# -- The tables ------------------------------------------------------------------------------

# boxes_read_jobs <uuid>  ->  refreshes the jobs cache; returns agentvm_jobs' status.
boxes_read_jobs() {
    local _file="$(boxes_cache "$1" jobs)"
    local _rows
    _rows="$(agentvm_jobs)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        agentvm_last_error "$_status" >/dev/null
        return "$_status"
    fi
    printf '%s\n' "$_rows" | boxes_store "$_file"
    return 0
}

# boxes_busy_kind <uuid> <target>  ->  the kind of the running job on target, from the cache.
# A job on several images names them all in one target ("image:dev,dev-node"), so an image is
# busy when its name is one of them.
boxes_busy_kind() {
    local _file="$(boxes_cache "$1" jobs)"
    [ -f "$_file" ] || return 0
    /usr/bin/awk -F'\t' -v target="$2" '
        $5 != "running" { next }
        $3 == target { print $2; exit }
        {
            split($3, side, ":"); split(target, want, ":")
            if (side[1] != want[1]) next
            n = split(substr($3, length(side[1]) + 2), name, ",")
            for (i = 1; i <= n; i++) if (side[1] ":" name[i] == target) { print $2; exit }
        }' "$_file"
}

# boxes_show_jobs <uuid>  ->  the jobs table and the progress bar of the newest running job.
# Rows: Job, State, Progress, then the job id hidden in column 4.
boxes_show_jobs() {
    local _uuid="$1"
    local _file="$(boxes_cache "$_uuid" jobs)"
    [ -f "$_file" ] || : > "$_file"
    /usr/bin/awk -F'\t' '
        {
            progress = $11
            if ($5 == "running" && $10 != "-") progress = sprintf("%d%% %s", $10 * 100, progress)
            if ($5 == "failed" || $5 == "lost") progress = $13
            if ($5 == "done" && progress == "-") progress = "finished"
            printf "%s\t%s\t%s\t%s\n", $4, $5, progress, $1
        }' "$_file" | "$dialog" "$_uuid" "$BOXES_JOBS_ID" omc_table_set_rows_from_stdin
    # The bar follows the newest running job that reported how far it is (an install, recipe
    # steps). A job without a fraction has its last step in the table instead.
    local _percent="$(/usr/bin/awk -F'\t' '$5 == "running" && $10 != "-" { last = $10 } END { if (last != "") printf "%d", last * 100 }' "$_file")"
    if [ -z "$_percent" ]; then
        "$dialog" "$_uuid" "$BOXES_PROGRESS_ID" omc_hide
        return 0
    fi
    "$dialog" "$_uuid" "$BOXES_PROGRESS_ID" "$_percent"
    "$dialog" "$_uuid" "$BOXES_PROGRESS_ID" omc_show
}

# boxes_running_count <uuid>  ->  how many cached jobs run.
boxes_running_count() {
    local _file="$(boxes_cache "$1" jobs)"
    [ -f "$_file" ] || { echo 0; return 0; }
    /usr/bin/awk -F'\t' '$5 == "running" { n++ } END { print n + 0 }' "$_file"
}

# boxes_read_images <uuid>  ->  refreshes the images cache (agentvm_images rows).
boxes_read_images() {
    local _rows
    _rows="$(agentvm_images)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        "$dialog" "$1" "$BOXES_NOTES_ID" "Could not list the images: $(agentvm_last_error "$_status")"
        return "$_status"
    fi
    printf '%s\n' "$_rows" | boxes_store "$(boxes_cache "$1" images)"
}

# boxes_read_boxes <uuid>  ->  refreshes the boxes cache (agentvm_boxes rows).
boxes_read_boxes() {
    local _rows
    _rows="$(agentvm_boxes)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        "$dialog" "$1" "$BOXES_NOTES_ID" "Could not list the boxes: $(agentvm_last_error "$_status")"
        return "$_status"
    fi
    printf '%s\n' "$_rows" | boxes_store "$(boxes_cache "$1" boxes)"
}

# boxes_busy_table <uuid>  ->  "target=kind" for every running job, space-separated, for the State
# columns. One line, because awk -v refuses a newline in a value. A job on several images
# ("image:dev,dev-node") gives one pair per image.
boxes_busy_table() {
    local _file="$(boxes_cache "$1" jobs)"
    [ -f "$_file" ] || return 0
    /usr/bin/awk -F'\t' '$5 == "running" {
        split($3, side, ":")
        n = split(substr($3, length(side[1]) + 2), name, ",")
        for (i = 1; i <= n; i++) printf "%s:%s=%s ", side[1], name[i], $2
    }' "$_file"
}

# boxes_show_images <uuid>  ->  the images table from the cache.
# Rows: Name, State, macOS, Based on, Own size, Needs.
boxes_show_images() {
    local _uuid="$1"
    local _file="$(boxes_cache "$_uuid" images)"
    [ -f "$_file" ] || : > "$_file"
    # "-" stays in empty cells, as in the other tables: a row is split on tabs.
    /usr/bin/awk -F'\t' -v held="$(boxes_busy_table "$_uuid")" '
        BEGIN {
            n = split(held, pair, " ")
            for (i = 1; i <= n; i++) {
                split(pair[i], part, "=")
                if (part[1] ~ /^image:/) kind[substr(part[1], 7)] = part[2]
            }
        }
        {
            state = $2
            if ($3 != "-") state = state " (" $3 ")"
            if ($1 in kind) state = kind[$1] == "update-guest" ? "updating..." : (kind[$1] == "image-setup" ? "setting up..." : (kind[$1] == "image-create" ? "building..." : "busy..."))
            printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, state, $4, $5, $6, $7
        }' "$_file" | "$dialog" "$_uuid" "$BOXES_IMAGES_ID" omc_table_set_rows_from_stdin
    boxes_show_updates "$_uuid"
}

# boxes_show_boxes <uuid>  ->  the boxes table from the cache.
# Rows: Name, State, Image, Network, CPUs, Memory, Own size.
boxes_show_boxes() {
    local _uuid="$1"
    local _file="$(boxes_cache "$_uuid" boxes)"
    [ -f "$_file" ] || : > "$_file"
    /usr/bin/awk -F'\t' -v held="$(boxes_busy_table "$_uuid")" '
        BEGIN {
            n = split(held, pair, " ")
            for (i = 1; i <= n; i++) {
                split(pair[i], part, "=")
                if (part[1] ~ /^box:/) kind[substr(part[1], 5)] = part[2]
            }
        }
        {
            state = $2 == "ready" ? "running" : $2
            if ($12 == "true") state = state ", disposable"
            if ($1 in kind) state = kind[$1] == "box-start" ? "starting..." : (kind[$1] == "box-stop" ? "stopping..." : "busy...")
            memory = $6 == "-" ? "-" : $6 " GB"
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, state, $3, $4, $5, memory, $7
        }' "$_file" | "$dialog" "$_uuid" "$BOXES_BOXES_ID" omc_table_set_rows_from_stdin
}

# boxes_show_kind <uuid> <images|boxes>  ->  shows that table and its buttons, hides the other.
boxes_show_kind() {
    local _uuid="$1"
    if [ "$2" = "boxes" ]; then
        "$dialog" "$_uuid" "$BOXES_IMAGES_ID" omc_hide
        "$dialog" "$_uuid" "$BOXES_BOXES_ID" omc_show
    else
        "$dialog" "$_uuid" "$BOXES_BOXES_ID" omc_hide
        "$dialog" "$_uuid" "$BOXES_IMAGES_ID" omc_show
    fi
}

# boxes_populate <uuid> [images]  ->  reads everything again and repaints the tables. Images
# are read only when asked ("images"): they are the slow list, and change only through jobs
# and deletes.
boxes_populate() {
    local _uuid="$1"
    boxes_read_jobs "$_uuid"
    if [ "${2:-}" = "images" ] || [ ! -f "$(boxes_cache "$_uuid" images)" ]; then
        boxes_read_images "$_uuid"
    fi
    boxes_read_boxes "$_uuid"
    boxes_show_jobs "$_uuid"
    boxes_show_images "$_uuid"
    boxes_show_boxes "$_uuid"
}

# -- The detail pane -------------------------------------------------------------------------

# boxes_clear_detail <uuid> [title]  ->  nothing selected: no text, no buttons.
boxes_clear_detail() {
    local _uuid="$1"
    "$pasteboard" "$(boxes_key cadabra_boxes_selected "$_uuid")" set ""
    "$dialog" "$_uuid" "$BOXES_TITLE_ID" "${2:-Select an image, a box or a job.}"
    "$dialog" "$_uuid" "$BOXES_SUBTITLE_ID" ""
    "$dialog" "$_uuid" "$BOXES_DETAIL_ID" ""
    "$dialog" "$_uuid" "$BOXES_IMAGE_BUTTONS_ID" omc_hide
    "$dialog" "$_uuid" "$BOXES_BOX_BUTTONS_ID" omc_hide
    "$dialog" "$_uuid" "$BOXES_JOB_CANCEL_ID" omc_disable
    "$dialog" "$_uuid" "$BOXES_JOB_FORGET_ID" omc_disable
}

# boxes_select_only <uuid> [table id]  ->  the other tables (all three without an id) lose
# their selection. The detail pane shows one item; a row left highlighted in another table
# could not be clicked to show it again, since a click on the selected row changes nothing and
# fires no action. omc_deselect fires no action either.
boxes_select_only() {
    local _id
    for _id in $BOXES_IMAGES_ID $BOXES_BOXES_ID $BOXES_JOBS_ID; do
        [ "$_id" = "${2:-}" ] || "$dialog" "$1" "$_id" omc_deselect
    done
}

# boxes_need_text <needKinds>  ->  what each need means and how to meet it.
boxes_need_text() {
    local _kinds=",$1,"
    case "$_kinds" in
        *,guest-update,*)
            printf '%s\n' "- Guest update: the image's agent-vm-guest is older than the one Cadabra runs with. Press Update Guest (it boots the image for a minute or two)." ;;
    esac
    case "$_kinds" in
        *,full-disk-access,*)
            printf '%s\n' "- Full Disk Access: programs in boxes of this image cannot read the shared project yet. Press Full Disk Access... and follow the steps shown." ;;
    esac
}

# boxes_show_image <uuid> <name>  ->  the image's details and the buttons that apply to it.
boxes_show_image() {
    local _uuid="$1" _name="$2"
    local _row="$(boxes_row "$(boxes_cache "$_uuid" images)" "$_name")"
    if [ -z "$_row" ]; then
        boxes_clear_detail "$_uuid"
        return 0
    fi
    "$pasteboard" "$(boxes_key cadabra_boxes_selected "$_uuid")" set "image:$_name"
    local _state="$(boxes_field "$_row" 2)"
    local _failure="$(boxes_field "$_row" 3)"
    local _path="$(boxes_field "$_row" 14)"
    local _kinds="$(boxes_field "$_row" 15)"
    local _busy="$(boxes_busy_kind "$_uuid" "image:$_name")"
    "$dialog" "$_uuid" "$BOXES_TITLE_ID" "Image $_name"
    if [ -n "$_busy" ]; then
        "$dialog" "$_uuid" "$BOXES_SUBTITLE_ID" "$(boxes_busy_word "$_busy")"
    else
        "$dialog" "$_uuid" "$BOXES_SUBTITLE_ID" "$_state${_failure:+ ($_failure)}"
    fi
    local _text
    _text="$(
        printf 'macOS:         %s\n' "$(boxes_field "$_row" 4)"
        printf 'Based on:      %s\n' "$(boxes_field "$_row" 5)"
        printf 'Recipe:        %s\n' "$(boxes_field "$_row" 8)"
        printf 'Created:       %s\n' "$(boxes_field "$_row" 9)"
        printf 'Guest daemon:  %s\n' "$(boxes_field "$_row" 10)"
        boxes_line 'CPUs:' "$(boxes_field "$_row" 11)"
        boxes_line 'Memory:' "$(boxes_field "$_row" 12)" GB
        boxes_line 'Disk:' "$(boxes_field "$_row" 13)" GB
        printf 'Own size:      %s (what deleting it frees)\n' "$(boxes_field "$_row" 6)"
        printf 'Folder:        %s\n' "$_path"
        if [ -n "$_kinds" ]; then
            printf '\nNeeds:\n'
            boxes_need_text "$_kinds"
        fi
    )"
    "$dialog" "$_uuid" "$BOXES_DETAIL_ID" "$_text"
    "$dialog" "$_uuid" "$BOXES_BOX_BUTTONS_ID" omc_hide
    "$dialog" "$_uuid" "$BOXES_IMAGE_BUTTONS_ID" omc_show
    "$dialog" "$_uuid" "$BOXES_JOB_CANCEL_ID" omc_disable
    "$dialog" "$_uuid" "$BOXES_JOB_FORGET_ID" omc_disable
    local _ready=0 _free=0
    [ "$_state" = "ready" ] && _ready=1
    [ -z "$_busy" ] && _free=1
    boxes_enable "$_uuid" "$BOXES_IMAGE_NEW_BOX_ID" "$_ready"
    boxes_enable "$_uuid" "$BOXES_IMAGE_NEW_FROM_ID" "$_ready"
    boxes_enable "$_uuid" "$BOXES_IMAGE_UPDATE_ID" "$((_ready * _free))"
    boxes_enable "$_uuid" "$BOXES_IMAGE_SETUP_ID" "$((_ready * _free))"
    boxes_enable "$_uuid" "$BOXES_IMAGE_REVEAL_ID" "$([ -n "$_path" ] && echo 1 || echo 0)"
    boxes_enable "$_uuid" "$BOXES_IMAGE_DELETE_ID" "$_free"
}

# boxes_show_box <uuid> <name>  ->  the box's details, its recent programs and refused hosts,
# and the buttons that apply to it.
boxes_show_box() {
    local _uuid="$1" _name="$2"
    local _row="$(boxes_row "$(boxes_cache "$_uuid" boxes)" "$_name")"
    if [ -z "$_row" ]; then
        boxes_clear_detail "$_uuid"
        return 0
    fi
    "$pasteboard" "$(boxes_key cadabra_boxes_selected "$_uuid")" set "box:$_name"
    local _state="$(boxes_field "$_row" 2)"
    local _path="$(boxes_field "$_row" 16)"
    local _busy="$(boxes_busy_kind "$_uuid" "box:$_name")"
    local _shown="$_state"
    [ "$_state" = "ready" ] && _shown="running"
    [ "$(boxes_field "$_row" 12)" = "true" ] && _shown="$_shown, disposable (deleted once it stops)"
    [ -n "$_busy" ] && _shown="$(boxes_busy_word "$_busy")"
    "$dialog" "$_uuid" "$BOXES_TITLE_ID" "Box $_name"
    "$dialog" "$_uuid" "$BOXES_SUBTITLE_ID" "$_shown"
    local _project="$(boxes_field "$_row" 9)"
    [ -n "$_project" ] && [ "$(boxes_field "$_row" 10)" = "true" ] && _project="$_project (read-only)"
    local _text
    _text="$(
        printf 'Image:         %s\n' "$(boxes_field "$_row" 3)"
        boxes_line 'CPUs:' "$(boxes_field "$_row" 5)"
        boxes_line 'Memory:' "$(boxes_field "$_row" 6)" GB
        printf 'Own size:      %s\n' "$(boxes_field "$_row" 7)"
        local _mode="$(boxes_field "$_row" 17)"
        printf 'Network:       %s\n' "$_mode"
        if [ "$_mode" = "allowlist" ]; then
            printf '%s\n' "$(boxes_field "$_row" 18)" | /usr/bin/tr ',' '\n' | /usr/bin/awk 'NF { print "  allowed:     " $0 }'
        fi
        if [ "$_state" = "ready" ]; then
            printf 'Project:       %s\n' "${_project:-none shared}"
            printf 'Programs:      %s running\n' "$(boxes_field "$_row" 11)"
            printf 'Started:       %s\n' "$(boxes_field "$_row" 14)"
            printf 'Supervisor:    pid %s, agent-vm %s\n' "$(boxes_field "$_row" 8)" "$(boxes_field "$_row" 15)"
            [ -n "$(boxes_field "$_row" 13)" ] && printf 'Stops when:    process %s exits\n' "$(boxes_field "$_row" 13)"
        fi
        printf 'Folder:        %s\n' "$_path"
        local _runs="$(agentvm_execlog "$_name" 8 2>/dev/null | /usr/bin/awk -F'\t' '{
            line = $1 "  " $4 "  -> " ($2 ~ /^[0123456789]+$/ ? "status " $2 : $2)
            if ($5 != "-") line = line "  (waited on: " $5 ")"
            print "  " line }')"
        printf '\nRecent programs:\n%s\n' "${_runs:-  none}"
        local _refused="$(agentvm_netlog "$_name" 8 denied 2>/dev/null | /usr/bin/awk -F'\t' '{ print "  " $1 "  " $3 ":" $4 "  (" $6 ")" }')"
        printf '\nRecently refused hosts:\n%s\n' "${_refused:-  none}"
    )"
    agentvm_last_error >/dev/null
    "$dialog" "$_uuid" "$BOXES_DETAIL_ID" "$_text"
    "$dialog" "$_uuid" "$BOXES_IMAGE_BUTTONS_ID" omc_hide
    "$dialog" "$_uuid" "$BOXES_BOX_BUTTONS_ID" omc_show
    "$dialog" "$_uuid" "$BOXES_JOB_CANCEL_ID" omc_disable
    "$dialog" "$_uuid" "$BOXES_JOB_FORGET_ID" omc_disable
    local _free=0 _running=0 _stopped=0
    [ -z "$_busy" ] && _free=1
    [ "$_state" = "ready" ] && _running=1
    [ "$_state" = "stopped" ] && _stopped=1
    boxes_enable "$_uuid" "$BOXES_BOX_START_ID" "$((_stopped * _free))"
    boxes_enable "$_uuid" "$BOXES_BOX_STOP_ID" "$(( (1 - _stopped) * _free ))"
    boxes_enable "$_uuid" "$BOXES_BOX_VIEW_ID" "$_running"
    boxes_enable "$_uuid" "$BOXES_BOX_CONTROL_ID" "$_running"
    boxes_enable "$_uuid" "$BOXES_BOX_SHELL_ID" "$_running"
    boxes_enable "$_uuid" "$BOXES_BOX_REVEAL_ID" "$([ -n "$_path" ] && echo 1 || echo 0)"
    boxes_enable "$_uuid" "$BOXES_BOX_DELETE_ID" "$((_stopped * _free))"
}

# boxes_show_job <uuid> <id>  ->  the job's details: what it runs, how far it got, its error.
boxes_show_job() {
    local _uuid="$1" _id="$2"
    local _row="$(/usr/bin/awk -F'\t' -v id="$_id" '$1 == id { print; exit }' "$(boxes_cache "$_uuid" jobs)" 2>/dev/null)"
    if [ -z "$_row" ]; then
        boxes_clear_detail "$_uuid"
        return 0
    fi
    "$pasteboard" "$(boxes_key cadabra_boxes_selected "$_uuid")" set "job:$_id"
    local _state="$(boxes_field "$_row" 5)"
    local _kind="$(boxes_field "$_row" 2)"
    "$dialog" "$_uuid" "$BOXES_TITLE_ID" "$(boxes_field "$_row" 4)"
    "$dialog" "$_uuid" "$BOXES_SUBTITLE_ID" "$_state"
    local _text
    _text="$(
        printf 'Started:       %s\n' "$(boxes_field "$_row" 7)"
        [ -n "$(boxes_field "$_row" 8)" ] && printf 'Ended:         %s\n' "$(boxes_field "$_row" 8)"
        [ -n "$(boxes_field "$_row" 6)" ] && printf 'Exit status:   %s\n' "$(boxes_field "$_row" 6)"
        [ -n "$(boxes_field "$_row" 11)" ] && printf 'Last step:     %s\n' "$(boxes_field "$_row" 11)"
        [ -n "$(boxes_field "$_row" 12)" ] && printf 'Note:          %s\n' "$(boxes_field "$_row" 12)"
        if [ "$_state" = "failed" ] || [ "$_state" = "lost" ]; then
            printf '\n%s\n' "$(agentvm_job_error "$_id" 2>/dev/null)"
        fi
        if [ "$_state" = "running" ] && [ "$_kind" = "image-setup" ]; then
            printf '\n%s\n' "In the image's window: open System Settings > Privacy & Security > Full Disk Access, drag agent-vm-guest into the list (it is in /usr/local/libexec), turn it on, enter the password if asked (the window's Type Password button types it), then close the window."
        fi
    )"
    agentvm_last_error >/dev/null
    "$dialog" "$_uuid" "$BOXES_DETAIL_ID" "$_text"
    "$dialog" "$_uuid" "$BOXES_IMAGE_BUTTONS_ID" omc_hide
    "$dialog" "$_uuid" "$BOXES_BOX_BUTTONS_ID" omc_hide
    local _running=0
    [ "$_state" = "running" ] && _running=1
    boxes_enable "$_uuid" "$BOXES_JOB_CANCEL_ID" "$_running"
    boxes_enable "$_uuid" "$BOXES_JOB_FORGET_ID" "$((1 - _running))"
}

# boxes_show_selected <uuid>  ->  repaints the detail pane for whatever it last showed.
boxes_show_selected() {
    local _selected="$("$pasteboard" "$(boxes_key cadabra_boxes_selected "$1")" get)"
    case "$_selected" in
        image:*) boxes_show_image "$1" "${_selected#image:}" ;;
        box:*)   boxes_show_box "$1" "${_selected#box:}" ;;
        job:*)   boxes_show_job "$1" "${_selected#job:}" ;;
    esac
}

# -- Jobs and the poll loop ------------------------------------------------------------------

# boxes_after_job_start <uuid> <job id>  ->  shows the new job and makes sure a poll loop runs.
# The job is put on the loop's watch list: one that ends before the loop's first pass (a quick
# failure) must still count as ended, so the lists it changed are read again.
boxes_after_job_start() {
    local _watch="$(boxes_key cadabra_boxes_watch "$1")"
    "$pasteboard" "$_watch" set "$("$pasteboard" "$_watch" get) $2"
    boxes_read_jobs "$1"
    boxes_show_jobs "$1"
    boxes_show_images "$1"
    boxes_show_boxes "$1"
    boxes_show_selected "$1"
    "$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.boxes.poll"
}

# boxes_poll <uuid>  ->  repaints the jobs while any runs; returns when none does, when a newer
# loop took over, or when the window closed. When a job ends, the lists it changed are read
# again: images after an image job, boxes after every job.
boxes_poll() {
    local _uuid="$1"
    local _key="$(boxes_key cadabra_boxes_poll "$_uuid")"
    local _token="poll-$$"
    # A loop chained by a handler that was still running when the window closed must not take
    # the token over "closed" and repaint a window that is gone for as long as the job runs.
    local _current="$("$pasteboard" "$_key" get)"
    [ "$_current" = "closed" ] && return 0
    "$pasteboard" "$_key" set "$_token"
    # Seeded with the jobs just started, whatever their state now; taken, so a later loop does
    # not count them again. Also seeded with what the loop this one takes over saw running on
    # its last pass (the "seen" key): a job that ended after that pass, and before this loop's
    # first, is an ended job to this loop, or neither loop would read the lists it changed.
    local _watch="$(boxes_key cadabra_boxes_watch "$_uuid")"
    local _seen="$(boxes_key cadabra_boxes_seen "$_uuid")"
    local _was="$("$pasteboard" "$_watch" get) $("$pasteboard" "$_seen" get) "
    "$pasteboard" "$_watch" set ""
    local _now _ended _kinds _built _extra
    local _holder
    while :; do
        _holder="$("$pasteboard" "$_key" get)"
        [ "$_holder" = "$_token" ] || return 0
        boxes_read_jobs "$_uuid"
        _now="$(/usr/bin/awk -F'\t' '$5 == "running" { printf "%s ", $1 }' "$(boxes_cache "$_uuid" jobs)")"
        "$pasteboard" "$_seen" set "$_now"
        # Jobs that ran on the last pass and do not now, with their kinds.
        _ended="$(/usr/bin/awk -F'\t' -v was=" $_was" '$5 != "running" && index(was, " " $1 " ") { print $2 }' "$(boxes_cache "$_uuid" jobs)")"
        if [ -n "$_ended" ]; then
            _kinds="$(printf '%s\n' "$_ended" | /usr/bin/tr '\n' ' ')"
            case " $_kinds" in
                *" update-guest "*|*" image-setup "*|*" image-create "*) boxes_read_images "$_uuid" ;;
            esac
            boxes_read_boxes "$_uuid"
            boxes_show_header "$_uuid" >/dev/null
        fi
        boxes_show_jobs "$_uuid"
        boxes_show_images "$_uuid"
        boxes_show_boxes "$_uuid"
        boxes_reselect "$_uuid"
        if [ -n "$_ended" ]; then
            boxes_show_selected "$_uuid"
            # A build or guest update may leave the image without Full Disk Access (a new guest
            # daemon has never been granted it): offer the setup now. A guest update that failed
            # partway still changed the images before the failure; their Needs say which.
            _built="$(/usr/bin/awk -F'\t' -v was=" $_was" '
                ($5 == "done" && ($2 == "image-create" || $2 == "update-guest") || $5 == "failed" && $2 == "update-guest") && index(was, " " $1 " ") {
                    n = split(substr($3, 7), name, ",")
                    # Once per image, however many finished jobs covered it.
                    for (i = 1; i <= n; i++) if (!(name[i] in seen)) { seen[name[i]] = 1; printf "%s ", name[i] }
                }' "$(boxes_cache "$_uuid" jobs)")"
            if [ -n "$_built" ]; then
                # The names are agent-vm names, so word splitting is safe.
                boxes_offer_setup "$_uuid" $_built
                # A setup the offer started is polled like any job: it joins this pass's set.
                _extra="$("$pasteboard" "$_watch" get)"
                "$pasteboard" "$_watch" set ""
                _now="$_now$_extra "
                case "$_now" in
                    *[!\ ]*) ;;
                    *) _now="" ;;
                esac
            fi
        fi
        [ -z "$_now" ] && break
        _was="$_now"
        /bin/sleep 1
    done
    _holder="$("$pasteboard" "$_key" get)"
    [ "$_holder" = "$_token" ] && "$pasteboard" "$_key" set ""
    return 0
}

# boxes_reselect <uuid>  ->  highlights the selected row again after a repaint. A row whose
# text changed (a State or a Progress) is a new row to the table, which drops its highlight.
# The verb fires no action, so the detail pane is left as it is.
boxes_reselect() {
    local _selected="$("$pasteboard" "$(boxes_key cadabra_boxes_selected "$1")" get)"
    case "$_selected" in
        image:*) "$dialog" "$1" "$BOXES_IMAGES_ID" omc_select_row_with_content "${_selected#image:}" 1 ;;
        box:*)   "$dialog" "$1" "$BOXES_BOXES_ID" omc_select_row_with_content "${_selected#box:}" 1 ;;
        job:*)   "$dialog" "$1" "$BOXES_JOBS_ID" omc_select_row_with_content "${_selected#job:}" 4 ;;
    esac
}

# -- Refreshing from other windows -----------------------------------------------------------

# boxes_refresh_manager  ->  the open Box Manager (if any) reads its boxes again.
boxes_refresh_manager() {
    local _uuid="$("$pasteboard" "$BOXES_MANAGER_KEY" get)"
    [ -n "$_uuid" ] || return 0
    boxes_read_jobs "$_uuid"
    boxes_read_boxes "$_uuid"
    boxes_show_boxes "$_uuid"
}

# -- The New Box window (aichat.boxes.box.new.json) -------------------------------------------

BOXES_NEW_NAME_ID=600
BOXES_NEW_IMAGE_ID=601
BOXES_NEW_CPUS_ID=602
BOXES_NEW_MEMORY_ID=603
BOXES_NEW_NETWORK_ID=604
BOXES_NEW_RULES_ID=605
BOXES_NEW_PACKS_ID=606
BOXES_NEW_DISPOSABLE_ID=607
BOXES_NEW_STATUS_ID=608
BOXES_NEW_CREATE_ID=609

# The image New Box... was pressed on, handed to the window it opens; read once.
BOXES_NEW_IMAGE_KEY="cadabra_boxes_new_image"

# boxes_new_images  ->  the ready images, one name per line: from the open Box Manager's cache
# when there is one, since `image list` is slow, else from agent-vm.
boxes_new_images() {
    local _manager="$("$pasteboard" "$BOXES_MANAGER_KEY" get)"
    local _cache=""
    [ -n "$_manager" ] && _cache="$(boxes_cache "$_manager" images)"
    if [ -n "$_cache" ] && [ -s "$_cache" ]; then
        /usr/bin/awk -F'\t' '$2 == "ready" { print $1 }' "$_cache"
        return 0
    fi
    local _rows
    _rows="$(agentvm_images)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' '$2 == "ready" { print $1 }'
}

# boxes_new_init <uuid>  ->  fills the window. The image picker's value is a 1-based index, so
# the ordered names are kept on the pasteboard for Create.
boxes_new_init() {
    local _uuid="$1"
    local _wanted="$("$pasteboard" "$BOXES_NEW_IMAGE_KEY" get)"
    "$pasteboard" "$BOXES_NEW_IMAGE_KEY" set ""
    local _images
    _images="$(boxes_new_images)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        "$dialog" "$_uuid" "$BOXES_NEW_STATUS_ID" "Could not list the images: $(agentvm_last_error "$_status")"
        "$dialog" "$_uuid" "$BOXES_NEW_CREATE_ID" omc_disable
        return 0
    fi
    if [ -z "$_images" ]; then
        "$dialog" "$_uuid" "$BOXES_NEW_STATUS_ID" "There is no ready image to make a box from."
        "$dialog" "$_uuid" "$BOXES_NEW_CREATE_ID" omc_disable
        return 0
    fi
    "$pasteboard" "$(boxes_key cadabra_boxes_new_images "$_uuid")" set "$_images"
    # Names are agent-vm names (letters, digits, ".", "_", "-"), so they need no JSON escaping.
    local _options="$(printf '%s\n' "$_images" | /usr/bin/awk 'NF { printf "%s\"%s\"", sep, $0; sep = "," } END { print "" }')"
    "$dialog" "$_uuid" "$BOXES_NEW_IMAGE_ID" omc_set_property options "[$_options]"
    local _index="$(printf '%s\n' "$_images" | /usr/bin/awk -v want="$_wanted" '$0 == want { print NR; exit }')"
    "$dialog" "$_uuid" "$BOXES_NEW_IMAGE_ID" "${_index:-1}"
    "$dialog" "$_uuid" "$BOXES_NEW_NETWORK_ID" "1"
    # A user pack agent-vm cannot use (its problem, since agent-vm 0.2.10) is named as broken: a
    # box that names it is refused, so offering it as if it worked would be a trap.
    local _packs="$(agentvm_packs 2>/dev/null | /usr/bin/awk -F'\t' '{ printf "%s%s%s", sep, $1, ($3 != "" && $3 != "-") ? " (broken: " $3 ")" : ""; sep = ", " }')"
    agentvm_last_error >/dev/null
    if [ -n "$_packs" ]; then
        "$dialog" "$_uuid" "$BOXES_NEW_PACKS_ID" "Packs name the hosts a tool needs, for example pack:npm. Known packs: $_packs."
    fi
}

# boxes_new_create <uuid>  ->  0 once the box exists; otherwise the reason is in the window's
# status line and it returns non-zero.
boxes_new_create() {
    local _uuid="$1"
    local _name="$OMC_ACTIONUI_VIEW_600_VALUE"
    local _index="$OMC_ACTIONUI_VIEW_601_VALUE"
    local _cpus="$OMC_ACTIONUI_VIEW_602_VALUE"
    local _memory="$OMC_ACTIONUI_VIEW_603_VALUE"
    local _rules="$OMC_ACTIONUI_VIEW_605_VALUE"
    local _net _disposable _image
    case "$OMC_ACTIONUI_VIEW_604_VALUE" in
        2) _net=off ;;
        3) _net=open ;;
        *) _net=allowlist ;;
    esac
    case "$OMC_ACTIONUI_VIEW_607_VALUE" in
        true) _disposable=yes ;;
        *)    _disposable=no ;;
    esac
    case "$_index" in
        ''|*[!0123456789]*) _image="" ;;
        *) _image="$("$pasteboard" "$(boxes_key cadabra_boxes_new_images "$_uuid")" get | /usr/bin/awk -v n="$_index" 'NR == n { print; exit }')" ;;
    esac
    if [ -z "$_name" ]; then
        "$dialog" "$_uuid" "$BOXES_NEW_STATUS_ID" "The box needs a name."
        return 2
    fi
    if [ -z "$_image" ]; then
        "$dialog" "$_uuid" "$BOXES_NEW_STATUS_ID" "Choose an image."
        return 2
    fi
    # One rule per line; blank lines and surrounding spaces do not count. The rules become the
    # positional parameters, which agentvm_box_create turns into --allow options, and only for
    # the allow list: the other modes take no rules.
    set --
    if [ "$_net" = "allowlist" ]; then
        local _line
        while IFS= read -r _line; do
            _line="$(printf '%s' "$_line" | /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            [ -n "$_line" ] && set -- "$@" "$_line"
        done <<RULES
$_rules
RULES
    fi
    "$dialog" "$_uuid" "$BOXES_NEW_STATUS_ID" "Creating $_name..."
    agentvm_box_create "$_name" "$_image" "$_cpus" "$_memory" "$_net" "$_disposable" "$@"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        "$dialog" "$_uuid" "$BOXES_NEW_STATUS_ID" "$(agentvm_last_error "$_status")"
        return "$_status"
    fi
    "$dialog" "$_uuid" "$BOXES_NEW_STATUS_ID" ""
    return 0
}

# -- The Box Manager coming back to the front, and jobs started from other windows -----------

BOXES_HEADER_NEW_IMAGE_ID=122
BOXES_IMAGE_NEW_FROM_ID=546

# boxes_activated <uuid>  ->  the Box Manager became the active window again: repaints the jobs,
# and starts a poll loop when jobs run (or a watched one ended unseen) and none is polling. A
# job started from another window
# (New Image) has no loop of its own, since a loop chained from there would run in that
# window's context; this is where one begins.
boxes_activated() {
    local _uuid="$1"
    boxes_read_jobs "$_uuid" || return 0
    boxes_show_jobs "$_uuid"
    boxes_show_images "$_uuid"
    boxes_show_boxes "$_uuid"
    local _running="$(boxes_running_count "$_uuid")"
    local _holder="$("$pasteboard" "$(boxes_key cadabra_boxes_poll "$_uuid")" get)"
    # A watched job that already ended (the window was elsewhere for the whole build, or
    # agent-vm refused at once) still needs one pass, which reads the lists it changed.
    local _watched="$("$pasteboard" "$(boxes_key cadabra_boxes_watch "$_uuid")" get | /usr/bin/tr -d ' ')"
    [ -n "$_watched" ] && _running=$((_running + 1))
    if [ "$_running" -gt 0 ] && [ -z "$_holder" ]; then
        "$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.boxes.poll"
    fi
}

# boxes_manager_job_started <job id>  ->  the open Box Manager (if any) lists a job another
# window started, and watches it: its next poll loop counts it as ended even if it ends before
# the loop's first pass.
boxes_manager_job_started() {
    local _uuid="$("$pasteboard" "$BOXES_MANAGER_KEY" get)"
    [ -n "$_uuid" ] || return 0
    local _watch="$(boxes_key cadabra_boxes_watch "$_uuid")"
    "$pasteboard" "$_watch" set "$("$pasteboard" "$_watch" get) $1"
    boxes_read_jobs "$_uuid"
    boxes_show_jobs "$_uuid"
    boxes_show_images "$_uuid"
}

# -- The New Image window (aichat.boxes.image.new.json) ---------------------------------------

BOXES_NI_NAME_ID=700
BOXES_NI_SOURCE_ID=701
BOXES_NI_IPSW_ID=711
BOXES_NI_IPSW_BROWSE_ID=712
BOXES_NI_BASE_ID=715
BOXES_NI_RECIPE_ID=720
BOXES_NI_RECIPE_FILE_ID=721
BOXES_NI_RECIPE_BROWSE_ID=722
BOXES_NI_CPUS_ID=730
BOXES_NI_MEMORY_ID=731
BOXES_NI_DISK_ID=732
BOXES_NI_ABOUT_ID=740
BOXES_NI_VALUES_ID=741
BOXES_NI_INPUT_BROWSE_ID=742
BOXES_NI_DECLS_ID=743
BOXES_NI_STATUS_ID=750
BOXES_NI_BUILD_ID=752

# The image "New Image from This..." was pressed on, handed to the window it opens; read once.
BOXES_NI_BASE_KEY="cadabra_boxes_new_image_base"

# _boxes_json_list  ->  stdin's lines as a JSON array of strings (for a Picker's options).
_boxes_json_list() {
    /usr/bin/awk 'BEGIN { printf "[" }
        { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s\"%s\"", sep, $0; sep = "," }
        END { print "]" }'
}

# boxes_ni_setting <uuid> <name>  ->  one of the window's remembered lists (images, recipes).
boxes_ni_setting() {
    "$pasteboard" "$(boxes_key "cadabra_boxes_ni_$2" "$1")" get
}

# boxes_ni_init <uuid>  ->  fills the window: the ready images for "An existing image" (the one
# "New Image from This..." was pressed on chosen), and the recipes Cadabra ships. Both pickers
# deliver 1-based indexes, so their ordered lists are kept on the pasteboard.
boxes_ni_init() {
    local _uuid="$1"
    local _wanted="$("$pasteboard" "$BOXES_NI_BASE_KEY" get)"
    "$pasteboard" "$BOXES_NI_BASE_KEY" set ""
    local _images
    _images="$(boxes_new_images)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "Could not list the images: $(agentvm_last_error "$_status")"
        _images=""
    fi
    "$pasteboard" "$(boxes_key cadabra_boxes_ni_images "$_uuid")" set "$_images"
    if [ -n "$_images" ]; then
        "$dialog" "$_uuid" "$BOXES_NI_BASE_ID" omc_set_property options "$(printf '%s\n' "$_images" | _boxes_json_list)"
    fi
    # Recipe picker: "None", each shipped recipe by its description up to the first " (",
    # then "A recipe file of your own".
    local _recipes="$(agentvm_recipes)"
    "$pasteboard" "$(boxes_key cadabra_boxes_ni_recipes "$_uuid")" set "$(printf '%s\n' "$_recipes" | /usr/bin/cut -f2)"
    "$dialog" "$_uuid" "$BOXES_NI_RECIPE_ID" omc_set_property options "$( {
        printf 'None\n'
        printf '%s\n' "$_recipes" | /usr/bin/awk -F'\t' 'NF { d = $3; i = index(d, " ("); if (i > 1) d = substr(d, 1, i - 1); print d }'
        printf 'A recipe file of your own\n'
    } | _boxes_json_list)"
    "$dialog" "$_uuid" "$BOXES_NI_RECIPE_ID" "1"
    local _index=""
    [ -n "$_wanted" ] && _index="$(printf '%s\n' "$_images" | /usr/bin/awk -v want="$_wanted" '$0 == want { print NR; exit }')"
    if [ -n "$_index" ]; then
        "$dialog" "$_uuid" "$BOXES_NI_SOURCE_ID" "2"
        "$dialog" "$_uuid" "$BOXES_NI_BASE_ID" "$_index"
        boxes_ni_source "$_uuid" 2
    else
        "$dialog" "$_uuid" "$BOXES_NI_SOURCE_ID" "1"
        [ -n "$_images" ] && "$dialog" "$_uuid" "$BOXES_NI_BASE_ID" "1"
        boxes_ni_source "$_uuid" 1
    fi
}

# boxes_ni_source <uuid> <1|2>  ->  enables the restore-image field (1) or the base picker (2).
boxes_ni_source() {
    if [ "$2" = "2" ]; then
        "$dialog" "$1" "$BOXES_NI_IPSW_ID" omc_disable
        "$dialog" "$1" "$BOXES_NI_IPSW_BROWSE_ID" omc_disable
        "$dialog" "$1" "$BOXES_NI_BASE_ID" omc_enable
    else
        "$dialog" "$1" "$BOXES_NI_BASE_ID" omc_disable
        "$dialog" "$1" "$BOXES_NI_IPSW_ID" omc_enable
        "$dialog" "$1" "$BOXES_NI_IPSW_BROWSE_ID" omc_enable
    fi
}

# boxes_ni_recipe_path <uuid> <picker index> <recipe file field>  ->  the recipe the picker
# names: nothing for "None", a shipped recipe's path, or the file field for the last option.
boxes_ni_recipe_path() {
    local _count="$(boxes_ni_setting "$1" recipes | /usr/bin/awk 'NF { n++ } END { print n + 0 }')"
    case "$2" in
        ''|*[!0123456789]*|1) return 0 ;;
    esac
    if [ "$2" -gt "$((_count + 1))" ]; then
        case "$3" in
            "~/"*) printf '%s\n' "$HOME/${3#"~/"}" ;;
            *)     printf '%s\n' "$3" ;;
        esac
        return 0
    fi
    boxes_ni_setting "$1" recipes | /usr/bin/awk -v n="$(($2 - 1))" 'NF && ++i == n { print; exit }'
}

# boxes_ni_show_recipe <uuid> <picker index> <recipe file field> <disk field>  ->  the recipe's
# description, its inputs and parameters as editable name=value lines (defaults filled in),
# and what each one means. The Xcode recipe gets a larger disk, as its README asks.
boxes_ni_show_recipe() {
    local _uuid="$1" _index="$2" _file="$3" _disk="$4"
    local _count="$(boxes_ni_setting "$_uuid" recipes | /usr/bin/awk 'NF { n++ } END { print n + 0 }')"
    local _own=0
    case "$_index" in
        ''|*[!0123456789]*) ;;
        *) [ "$_index" -gt "$((_count + 1))" ] && _own=1 ;;
    esac
    boxes_enable "$_uuid" "$BOXES_NI_RECIPE_FILE_ID" "$_own"
    boxes_enable "$_uuid" "$BOXES_NI_RECIPE_BROWSE_ID" "$_own"
    "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" ""
    local _path="$(boxes_ni_recipe_path "$_uuid" "$_index" "$_file")"
    local _rows=""
    local _status=0
    if [ -n "$_path" ]; then
        _rows="$(agentvm_recipe_info "$_path")"
        _status=$?
    fi
    # No recipe, or one that cannot be read: nothing of the previous recipe stays on show.
    if [ -z "$_path" ] || [ "$_status" -ne 0 ]; then
        "$dialog" "$_uuid" "$BOXES_NI_ABOUT_ID" ""
        "$dialog" "$_uuid" "$BOXES_NI_VALUES_ID" ""
        "$dialog" "$_uuid" "$BOXES_NI_DECLS_ID" ""
        "$dialog" "$_uuid" "$BOXES_NI_INPUT_BROWSE_ID" omc_disable
        [ "$_status" -ne 0 ] && "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "$(agentvm_last_error "$_status")"
        return 0
    fi
    "$dialog" "$_uuid" "$BOXES_NI_ABOUT_ID" "$(printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' '$1 == "recipe" && $5 != "-" { print $5 }')"
    "$dialog" "$_uuid" "$BOXES_NI_VALUES_ID" "$(printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' '
        $1 == "input"     { print $2 "=" }
        $1 == "parameter" { print $2 "=" ($4 == "-" ? "" : $4) }')"
    "$dialog" "$_uuid" "$BOXES_NI_DECLS_ID" "$(printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' '
        $1 == "input"     { print $2 " (a file): " $5 }
        $1 == "parameter" { print $2 ": " ($5 == "-" ? "" : $5) ($3 == "true" ? " (required)" : "") }')"
    local _inputs="$(printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' '$1 == "input" { n++ } END { print n + 0 }')"
    boxes_enable "$_uuid" "$BOXES_NI_INPUT_BROWSE_ID" "$([ "$_inputs" -gt 0 ] && echo 1 || echo 0)"
    if [ "$(/usr/bin/basename "$(/usr/bin/dirname "$_path")")" = "xcode" ] && [ -z "$_disk" ]; then
        "$dialog" "$_uuid" "$BOXES_NI_DISK_ID" "128"
    fi
}

# boxes_ni_set_input <values text> <recipe.json> <file>  ->  the values text with the recipe's
# first input set to file (the line replaced, or added when missing).
boxes_ni_set_input() {
    local _input="$(agentvm_recipe_info "$2" 2>/dev/null | /usr/bin/awk -F'\t' '$1 == "input" { print $2; exit }')"
    agentvm_last_error >/dev/null
    if [ -z "$_input" ]; then
        printf '%s\n' "$1"
        return 0
    fi
    # The file comes through the environment: awk -v turns a backslash in a file name into an
    # escape sequence.
    printf '%s\n' "$1" | BOXES_NI_FILE="$3" /usr/bin/awk -v name="$_input" '
        BEGIN { file = ENVIRON["BOXES_NI_FILE"] }
        { line = $0; sub(/^[ \t]+/, "", line) }
        index(line, name "=") == 1 && !done { print name "=" file; done = 1; next }
        { print }
        END { if (!done) print name "=" file }' | /usr/bin/awk 'NF || seen { print; seen = 1 }'
}

# boxes_ni_create <uuid>  ->  0 once the build started as a job (its id is in $boxes_ni_job);
# otherwise the reason is in the window's status line and it returns non-zero.
boxes_ni_create() {
    local _uuid="$1"
    local _name="$OMC_ACTIONUI_VIEW_700_VALUE"
    local _ipsw="$OMC_ACTIONUI_VIEW_711_VALUE"
    local _recipe="$(boxes_ni_recipe_path "$_uuid" "$OMC_ACTIONUI_VIEW_720_VALUE" "$OMC_ACTIONUI_VIEW_721_VALUE")"
    local _kind _source
    boxes_ni_job=""
    case "$_ipsw" in
        "~/"*) _ipsw="$HOME/${_ipsw#"~/"}" ;;
    esac
    if [ "$OMC_ACTIONUI_VIEW_701_VALUE" = "2" ]; then
        _kind=from
        case "$OMC_ACTIONUI_VIEW_715_VALUE" in
            ''|*[!0123456789]*) _source="" ;;
            *) _source="$(boxes_ni_setting "$_uuid" images | /usr/bin/awk -v n="$OMC_ACTIONUI_VIEW_715_VALUE" 'NF && ++i == n { print; exit }')" ;;
        esac
        if [ -z "$_source" ]; then
            "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "Choose the image to start from."
            return 2
        fi
    else
        _kind=ipsw
        _source="$_ipsw"
        if [ -z "$_source" ]; then
            "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "Choose a macOS restore image (.ipsw)."
            return 2
        fi
    fi
    if [ -z "$_name" ]; then
        "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "The image needs a name."
        return 2
    fi
    # The values: name=value lines. A name the recipe declares as an input becomes input:, any
    # other set: (agent-vm refuses a name the recipe does not declare, with its own message).
    # A recipe that cannot be read is refused here, while the window still holds the fields.
    local _inputs="" _required="" _declared=""
    if [ -n "$_recipe" ]; then
        local _decls
        _decls="$(agentvm_recipe_info "$_recipe")"
        local _decls_status=$?
        if [ "$_decls_status" -ne 0 ]; then
            "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "$(agentvm_last_error "$_decls_status")"
            return "$_decls_status"
        fi
        _inputs=" $(printf '%s\n' "$_decls" | /usr/bin/awk -F'\t' '$1 == "input" { printf "%s ", $2 }')"
        # Parameters without a default: the prefilled "name=" line would set them to empty
        # text, which agent-vm accepts, so its "must be set" check never fires.
        _required=" $(printf '%s\n' "$_decls" | /usr/bin/awk -F'\t' '$1 == "parameter" && $3 == "true" { printf "%s ", $2 }')"
        # Every name the recipe declares: a misspelled one is refused here, where the fields
        # can still be corrected, rather than by agent-vm after the window has closed.
        _declared=" $(printf '%s\n' "$_decls" | /usr/bin/awk -F'\t' '$1 == "input" || $1 == "parameter" { printf "%s ", $2 }')"
    fi
    set --
    local _line _key _value
    while IFS= read -r _line; do
        _line="$(printf '%s' "$_line" | /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        case "$_line" in
            ''|'#'*) continue ;;
            *=*) ;;
            *) "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "\"$_line\" is not a name=value line."
               return 2 ;;
        esac
        [ -n "$_recipe" ] || continue
        _key="${_line%%=*}"
        _value="${_line#*=}"
        case "$_declared" in
            *" $_key "*) ;;
            *) "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "The recipe has no input or parameter named \"$_key\"."
               return 2 ;;
        esac
        case "$_inputs" in
            *" $_key "*)
                case "$_value" in
                    "~/"*) _value="$HOME/${_value#"~/"}" ;;
                esac
                if [ -z "$_value" ]; then
                    "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "The recipe input $_key needs a file."
                    return 2
                fi
                set -- "$@" "input:$_key=$_value" ;;
            *)
                case "$_required" in
                    *" $_key "*)
                        if [ -z "$_value" ]; then
                            "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "The recipe parameter $_key needs a value."
                            return 2
                        fi ;;
                esac
                set -- "$@" "set:$_key=$_value" ;;
        esac
    done <<VALUES
$OMC_ACTIONUI_VIEW_741_VALUE
VALUES
    "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "Starting the build..."
    boxes_ni_job="$(agentvm_image_create_job "$_name" "$_kind" "$_source" "$_recipe" \
        "$OMC_ACTIONUI_VIEW_730_VALUE" "$OMC_ACTIONUI_VIEW_731_VALUE" "$OMC_ACTIONUI_VIEW_732_VALUE" "$@")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        "$dialog" "$_uuid" "$BOXES_NI_STATUS_ID" "$(agentvm_last_error "$_status")"
        return "$_status"
    fi
    return 0
}

# boxes_ni_forget <uuid>  ->  the window's pasteboard lists, when it closes.
boxes_ni_forget() {
    "$pasteboard" "$(boxes_key cadabra_boxes_ni_images "$1")" set ""
    "$pasteboard" "$(boxes_key cadabra_boxes_ni_recipes "$1")" set ""
}

# -- Images that need something: Update All, and Full Disk Access after a build -------------

BOXES_UPDATES_TEXT_ID=133
BOXES_UPDATE_ALL_ID=132

# boxes_update_candidates <uuid>  ->  the ready images whose guest daemon lacks features of this
# agent-vm's (need "guest-update") and that no job holds, one name per line, from the cache.
boxes_update_candidates() {
    local _file="$(boxes_cache "$1" images)"
    [ -f "$_file" ] || return 0
    /usr/bin/awk -F'\t' -v held="$(boxes_busy_table "$1")" '
        BEGIN {
            n = split(held, pair, " ")
            for (i = 1; i <= n; i++) { split(pair[i], part, "="); if (part[1] ~ /^image:/) busy[substr(part[1], 7)] = 1 }
        }
        $2 == "ready" && ("," $15 ",") ~ /,guest-update,/ && !($1 in busy) { print $1 }' "$_file"
}

# boxes_show_updates <uuid>  ->  "N images need a guest update" with Update All beside it, or
# neither. After an agent-vm update (the bundled one, or a developer build) every image built
# before it needs this, which is why it is one button rather than one per image.
boxes_show_updates() {
    local _uuid="$1"
    local _count="$(boxes_update_candidates "$_uuid" | /usr/bin/awk 'NF { n++ } END { print n + 0 }')"
    if [ "$_count" -eq 0 ]; then
        "$dialog" "$_uuid" "$BOXES_UPDATES_TEXT_ID" ""
        "$dialog" "$_uuid" "$BOXES_UPDATE_ALL_ID" omc_hide
        return 0
    fi
    if [ "$_count" -eq 1 ]; then
        "$dialog" "$_uuid" "$BOXES_UPDATES_TEXT_ID" "1 image needs a guest update"
    else
        "$dialog" "$_uuid" "$BOXES_UPDATES_TEXT_ID" "$_count images need a guest update"
    fi
    "$dialog" "$_uuid" "$BOXES_UPDATE_ALL_ID" omc_show
}

# boxes_update_all <uuid>  ->  asks, then updates every candidate in one job; 0 when started or
# declined, otherwise agent-vm's or the library's refusal is shown in an alert.
boxes_update_all() {
    local _uuid="$1"
    local _images="$(boxes_update_candidates "$_uuid")"
    [ -n "$_images" ] || return 0
    local _list="$(printf '%s\n' "$_images" | /usr/bin/awk 'NF { printf "%s%s", sep, $0; sep = ", " }')"
    "$alert" --level caution --title "Update the guest in these images?" --ok "Update All" --cancel "Cancel" \
        "$_list. Each image is booted in turn, a minute or two each, to install the agent-vm-guest that comes with this agent-vm. Boxes made from them before keep their old guest until they are made again."
    if [ $? -ne 0 ]; then
        return 0
    fi
    # The names are agent-vm names (letters, digits, ".", "_", "-"), so word splitting is safe.
    local _job
    _job="$(agentvm_image_update_guest_job $_images)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        boxes_alert_error "Could not start the guest update" "$_status"
        return 0
    fi
    boxes_after_job_start "$_uuid" "$_job"
}

# boxes_offer_setup <uuid> <images...>  ->  of the images a finished job just built or updated,
# the ready ones that need Full Disk Access (their guest daemon has no grant, or a new daemon
# was never checked); offers to set up the first now, naming the rest. Without it, programs in
# their boxes cannot read the shared project. One offer and at most one setup per pass: each
# setup is an interactive VM window, and macOS runs two VMs at most, so after Update All a
# setup per image would soon be refused. The others keep their Needs, and their own Full Disk
# Access... button.
boxes_offer_setup() {
    local _uuid="$1"
    shift
    local _file="$(boxes_cache "$_uuid" images)"
    local _image _row _state _kinds _need=""
    for _image in "$@"; do
        _row="$(boxes_row "$_file" "$_image")"
        _state="$(boxes_field "$_row" 2)"
        _kinds="$(boxes_field "$_row" 15)"
        [ "$_state" = "ready" ] || continue
        case ",$_kinds," in
            *,full-disk-access,*) _need="${_need:+$_need }$_image" ;;
        esac
    done
    [ -n "$_need" ] || return 0
    local _first="${_need%% *}"
    local _others=""
    [ "$_need" != "$_first" ] && _others="${_need#* }"
    local _more=""
    if [ -n "$_others" ]; then
        _more=" It is needed in $(printf '%s' "$_others" | /usr/bin/sed 's/ /, /g') too: set those up one at a time afterwards, with each image's Full Disk Access... button."
    fi
    "$alert" --level note --title "Set up Full Disk Access in $_first?" --ok "Set Up Now" --cancel "Later" \
        "Programs in boxes made from $_first cannot read the shared project until agent-vm-guest has Full Disk Access. Setting it up opens the image in a window: open System Settings > Privacy & Security > Full Disk Access, drag agent-vm-guest into the list (it is in /usr/local/libexec), turn it on, and enter the password if asked (the window's Type Password button types it). Then close the window.$_more"
    if [ $? -ne 0 ]; then
        return 0
    fi
    local _job
    _job="$(agentvm_image_setup_job "$_first")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        boxes_alert_error "Could not open $_first" "$_status"
        return 0
    fi
    local _watch="$(boxes_key cadabra_boxes_watch "$_uuid")"
    "$pasteboard" "$_watch" set "$("$pasteboard" "$_watch" get) $_job"
}
