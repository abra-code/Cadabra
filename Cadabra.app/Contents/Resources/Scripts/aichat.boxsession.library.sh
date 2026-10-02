#!/bin/sh
# aichat.boxsession.library.sh
#
# A chat window's external ACP agent run in an agent-vm box: the box it runs in, the transport
# that runs it there, and the registry that lets Cadabra release the box when the window goes.
#
# WHERE IT RUNS ("run-in"), as the Select ACP Agent window stores the choice:
#   mac           this Mac, no box; nothing in this file applies
#   box:<name>    a kept box: started if stopped, left running afterwards
#   new:<image>   a disposable box from <image>, made for this window and gone after it
#
# THE REGISTRY, $mcp_app_support/box-sessions.tsv, one row per window with a boxed agent:
#   window, box, disposable (yes or no), project, readOnly (yes or no), cadabraPid
# A row is written before the box starts, so a start that fails half way is released like any
# other. Every change rewrites the file whole under a lock and moves it into place, because
# window-close handlers and the launch-time cleanup can run at the same moment.
#
# RELEASE. When no row names a box any more, a disposable box goes: deleted at once when it is
# stopped, otherwise stopped by a job (so it outlives the handler), after which agent-vm never
# starts it again and its `box gc` (run by box list, box start and doctor) deletes it. A kept box
# is left running here. A box Cadabra started also stops by itself when Cadabra exits, however
# it exits, through its owner lease (agentvm_box_start passes --owner-pid).
#
# THE STOP QUESTION. A running kept box holds one of the two virtual machine slots and its
# memory, so when the last window using it closes, boxsession_close asks whether to stop it,
# and while windows use it the box line says it stays running. Asked only at a window close:
# never at quit (the owner lease stops what Cadabra started), at launch, or when a window gives
# up its box to start again.
[ -n "${__AICHAT_BOXSESSION_LIB:-}" ] && return 0
__AICHAT_BOXSESSION_LIB=1

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
# The per-agent key choice (acp_agent_secret), read by boxsession_secret.
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.acp.agents.library.sh"

boxsession_catalog_py="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/acp_catalog.py"
boxsession_transport_py="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/acp_transport_json.py"

boxsession_tab="$(printf '\t')"
boxsession_newline="
"

# boxsession_registry_file  ->  the registry's path.
boxsession_registry_file() {
    printf '%s\n' "$mcp_app_support/box-sessions.tsv"
}

# _boxsession_lock [lock [stale seconds]] / _boxsession_unlock [lock] - the registry's lock, or
# another lock folder by its path (aichat.snapshot.library.sh's start lock), a directory (mkdir is
# atomic). [stale seconds] replaces the 30 s below for a lock held across longer work.
# A lock older than 30 s is left over from a killed handler and is taken over, by renaming it
# away (only one contender's rename succeeds). A waiter gives up after about 10 s and returns 1:
# the caller then leaves the registry alone rather than rewrite it unlocked. Every pass counts
# toward that limit, a takeover too, so a lock that cannot be made (an unwritable folder) ends
# the wait instead of looping; a lock that vanished between mkdir and stat is simply retried.
_boxsession_lock() {
    local _lock="${1:-$mcp_app_support/box-sessions.lock}"
    local _tries=0 _made _mtime _now
    /bin/mkdir -p "$mcp_app_support" 2>/dev/null
    while [ "$_tries" -lt 100 ]; do
        /bin/mkdir "$_lock" 2>/dev/null
        _made=$?
        if [ "$_made" -eq 0 ]; then
            return 0
        fi
        _tries=$((_tries + 1))
        _mtime="$(/usr/bin/stat -f%m "$_lock" 2>/dev/null)"
        _now="$(/bin/date +%s)"
        if [ -n "$_mtime" ] && [ $((_now - _mtime)) -gt "${2:-30}" ]; then
            /bin/mv "$_lock" "$_lock.stale.$$" 2>/dev/null
            /bin/rm -rf "$_lock.stale.$$"
            continue
        fi
        /bin/sleep 0.1
    done
    return 1
}

_boxsession_unlock() {
    /bin/rmdir "${1:-$mcp_app_support/box-sessions.lock}" 2>/dev/null
}

# _boxsession_rewrite <awk program> <window> [row]  ->  the registry rewritten through the awk
# program (which prints the rows to keep), under the lock. The program reads the window and the
# row as ENVIRON["boxsession_window"] and ENVIRON["boxsession_row"]: awk -v would turn a "\n"
# or "\t" spelled in a project path into a real line break or tab, past the check for them.
# Status 1, with the reason left for agentvm_last_error, when the lock could not be had or the
# file could not be replaced.
_boxsession_rewrite() {
    _boxsession_rewrite_file "$(boxsession_registry_file)" "$@"
}

# _boxsession_rewrite_file <file> <awk program> <window> [row]  ->  _boxsession_rewrite for another
# registry kept the same way (aichat.snapshot.library.sh's), under the same lock.
_boxsession_rewrite_file() {
    local _file="$1" _program="$2" _window="$3" _row="${4:-}"
    _boxsession_lock
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        _agentvm_refuse 1 "The AgentVM session list ($_file) is locked by another Cadabra task, or its folder cannot be written."
        return 1
    fi
    local _tmp="$_file.tmp.$$"
    if [ -f "$_file" ]; then
        boxsession_window="$_window" boxsession_row="$_row" /usr/bin/awk -F'\t' "$_program" "$_file" > "$_tmp"
    else
        boxsession_window="$_window" boxsession_row="$_row" /usr/bin/awk -F'\t' "$_program" /dev/null > "$_tmp"
    fi
    _status=$?
    if [ "$_status" -eq 0 ]; then
        /bin/mv -f "$_tmp" "$_file"
        _status=$?
    fi
    /bin/rm -f "$_tmp"
    _boxsession_unlock
    if [ "$_status" -ne 0 ]; then
        _agentvm_refuse 1 "The AgentVM session list ($_file) could not be rewritten."
        return 1
    fi
    return 0
}

# boxsession_registry_add <window> <box> <yes|no disposable> <project> <yes|no read-only>
# Replaces the window's row if it has one. Refuses a field holding a tab or a line break, which
# would break the file's rows.
boxsession_registry_add() {
    if [ $# -ne 5 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$4" ]; then
        _agentvm_refuse 2 "boxsession_registry_add needs a window, a box, yes or no, a project and yes or no."
        return 2
    fi
    # An empty or other value here would shift the fields boxsession_release_stale reads (its
    # tab-separated read joins adjacent tabs), making a live window's row look stale.
    case "$3:$5" in
        yes:yes|yes:no|no:yes|no:no) ;;
        *) _agentvm_refuse 2 "disposable and read-only must each be yes or no, not \"$3\" and \"$5\"."
           return 2 ;;
    esac
    local _field
    for _field in "$@"; do
        case "$_field" in
            *"$boxsession_tab"*|*"$boxsession_newline"*)
                _agentvm_refuse 2 "A tab or a line break cannot be part of an AgentVM box session's window, box or project."
                return 2 ;;
        esac
    done
    local _pid="$(_agentvm_owner_pid)"
    local _row="$1$boxsession_tab$2$boxsession_tab$3$boxsession_tab$4$boxsession_tab$5$boxsession_tab${_pid:--}"
    _boxsession_rewrite '$1 != ENVIRON["boxsession_window"] { print } END { print ENVIRON["boxsession_row"] }' "$1" "$_row"
}

# boxsession_registry_rows  ->  the registry's rows (nothing when there is none).
boxsession_registry_rows() {
    local _file="$(boxsession_registry_file)"
    if [ -f "$_file" ]; then
        /bin/cat "$_file"
    fi
}

# boxsession_registry_row <window>  ->  the window's row, or nothing.
boxsession_registry_row() {
    boxsession_registry_rows | boxsession_window="$1" /usr/bin/awk -F'\t' '$1 == ENVIRON["boxsession_window"] { print; exit }'
}

# boxsession_stamp_image <window> <box> <image>  ->  remembers the image a window's disposable box
# was made from, for the conversation's record (boxsession_meta_fields). The registry does not
# keep it, and asking agent-vm when the first message is saved would slow that handler.
boxsession_stamp_image() {
    pb_set "aichatv2_boximage_$1" "$2$boxsession_tab$3"
}

# boxsession_meta_fields <window>  ->  one line for the conversation's record, tab separated:
# box, image, disposable (yes or no), project, readOnly (yes or no); nothing when the window has
# no box. The image is the stamped one when the stamp names the same box (a disposable box),
# else "-": a stamp left by an earlier launch of the window names another box. Never an empty
# field, since a reader splitting on tabs (IFS whitespace) would merge it with the next one.
boxsession_meta_fields() {
    local _row="$(boxsession_registry_row "$1")"
    if [ -z "$_row" ]; then
        return 0
    fi
    local _box="$(printf '%s\n' "$_row" | /usr/bin/cut -f2)"
    local _stamp="$(pb_get "aichatv2_boximage_$1")"
    local _image="-"
    if [ "${_stamp%%"$boxsession_tab"*}" = "$_box" ]; then
        _image="${_stamp#*"$boxsession_tab"}"
    fi
    if [ -z "$_image" ]; then
        _image="-"
    fi
    printf '%s\n' "$_row" | /usr/bin/awk -F'\t' -v image="$_image" 'BEGIN { OFS = "\t" } { print $2, image, $3, $4, $5 }'
}

# THE BOX LINE, under the model button of a chat window whose agent runs in a box (a Label and
# a Network... button in a row put into the empty slot 543 of aichat.chat.json, so windows
# without a box keep their layout; the button opens aichat.box.network.json):
#   AgentVM box s3, project read-only - 4 hosts reached, 2 refused
# Its tooltip names the hosts. The counts cover the connections of every program in the box
# since the agent started, from agent-vm's network log; the chat entry handler refreshes them
# in the background after each message, and aichat.chat.activated.sh when the window comes to the
# front (boxsession_line_focus). The line also counts the macOS permission prompts those
# programs met (" - 1 permission prompt", from the exec log), and the refresh that first finds
# one tells the user in an alert. The window's pasteboard key aichatv2_boxline_<window>
# holds what the refreshes need: box TAB since TAB the line's first part, and
# aichatv2_boxline_at_<window> the time of the last refresh, in seconds since 1970.
# The line's text is set as the Label's value, not with omc_set_property title: a Label shows its
# value, which ActionUI seeds from the title once, at insertion, so a later title change is not
# shown. The tooltip (help) has no such value and is set as a property.
boxsession_line_slot_id=543
boxsession_line_id=544
# The row holding the line and its Network... button (aichat.chat.box.network.sh).
boxsession_line_row_id=545
boxsession_line_network_id=546
# How many of the network log's last entries a refresh reads. The log of a kept box grows over
# every session it served (up to 64 MB); agent-vm reads its last entries from the end (0.3.8), and
# the rows converted and counted here stay few. The most _agentvm_need_count accepts.
boxsession_line_netlog_last=999
# How many of the exec log's last runs a refresh reads for permission prompts. The agent is one
# long run; the programs it starts in the box are not runs of their own.
boxsession_line_execlog_last=200
# How many host names the tooltip lists of each kind.
boxsession_line_hosts_shown=6

# boxsession_line_head <window>  ->  the line's first part, from the registry row and the image
# stamp: "Kept AgentVM box s3 (stays running)", "Disposable AgentVM box cadabra-opencode-3f2a91
# from dev-agents", with ", project read-only" when so; nothing when the window has no row.
boxsession_line_head() {
    local _fields="$(boxsession_meta_fields "$1")"
    if [ -z "$_fields" ]; then
        return 0
    fi
    printf '%s\n' "$_fields" | /usr/bin/awk -F'\t' '{
        if ($3 == "yes") {
            head = "Disposable AgentVM box " $1
            if ($2 != "-") head = head " from " $2
        } else {
            head = "Kept AgentVM box " $1 " (stays running)"
        }
        if ($5 == "yes") head = head ", project read-only"
        print head
    }'
}

# _boxsession_kept_note <window>  ->  the tooltip's sentence on a kept box, or nothing for a disposable
# box or a window with no row.
_boxsession_kept_note() {
    local _disposable="$(boxsession_registry_row "$1" | /usr/bin/cut -f3)"
    if [ "$_disposable" = "no" ]; then
        printf '%s\n' "A kept box keeps running when its chat windows close, holding one of the two virtual machine slots on this Mac, unless you stop it: closing the last window that uses it asks."
    fi
}

# boxsession_line_show <window> <box> [agent id]  ->  puts the line in the window, and remembers
# the box, this moment and the line's first part for the refreshes, and the agent id for the
# Network window's Allow for <agent> (aichatv2_boxagent_<window>).
# Called once the agent's box runs, so the connections macOS makes while the box boots are
# not counted as the agent's.
boxsession_line_show() {
    local _since="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
    local _head="$(boxsession_line_head "$1")"
    if [ -z "$_head" ]; then
        _head="AgentVM box $2"
    fi
    pb_set "aichatv2_boxline_$1" "$2$boxsession_tab$_since$boxsession_tab$_head"
    pb_set "aichatv2_boxagent_$1" "${3:-}"
    pb_set "aichatv2_boxprompts_$1" ""
    "$dialog" "$1" "$boxsession_line_row_id" omc_remove_element 2>/dev/null
    "$dialog" "$1" "$boxsession_line_slot_id" omc_insert_element "{\"type\":\"HStack\",\"id\":$boxsession_line_row_id,\"properties\":{\"spacing\":8,\"padding\":{\"top\":0,\"leading\":14,\"bottom\":6,\"trailing\":14},\"frame\":{\"maxWidth\":\"infinity\",\"alignment\":\"leading\"}},\"children\":[{\"type\":\"Label\",\"id\":$boxsession_line_id,\"properties\":{\"title\":\"\",\"systemImage\":\"shippingbox\",\"font\":\"footnote\",\"foregroundStyle\":\"secondary\",\"frame\":{\"maxWidth\":\"infinity\",\"alignment\":\"leading\"}}},{\"type\":\"Button\",\"id\":$boxsession_line_network_id,\"properties\":{\"title\":\"Network...\",\"buttonStyle\":\"bordered\",\"controlSize\":\"small\",\"help\":\"The hosts programs in the AgentVM box reached and were refused, and allowing a refused one\",\"actionID\":\"aichat.chat.box.network\"}}]}"
    "$dialog" "$1" "$boxsession_line_id" "$_head - no connections yet"
    local _help="Programs in the AgentVM box reach only the hosts its rules allow. The counts start when the agent does."
    local _kept="$(_boxsession_kept_note "$1")"
    if [ -n "$_kept" ]; then
        _help="$_help$boxsession_newline$_kept"
    fi
    "$dialog" "$1" "$boxsession_line_id" omc_set_property help "$_help"
}

# boxsession_net_counts <box> <since>  ->  one row from the box's network log since <since> (an
# ISO 8601 UTC time, as agent-vm writes them): hosts reached, refused, failed (allowed, but the
# connection failed), then each kind's host names, comma-joined ("-" for none), then "yes" when
# the log's last entries read did not reach back to <since>. Hosts are counted once each.
# agent-vm's status on failure, with its reason left for agentvm_last_error.
boxsession_net_counts() {
    local _rows
    _rows="$(agentvm_netlog "$1" "$boxsession_line_netlog_last")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' -v since="$2" -v limit="$boxsession_line_netlog_last" '
        function add(kind, host) {
            if ((kind SUBSEP host) in seen) return
            seen[kind, host] = 1
            count[kind]++
            list[kind] = list[kind] (count[kind] > 1 ? "," : "") host
        }
        NF == 0 { next }
        { rows++ }
        rows == 1 { first = $1 }
        $1 >= since {
            if ($2 == "allowed") add("allowed", $3)
            else if ($2 == "denied") add("denied", $3)
            else if ($2 == "failed") add("failed", $3)
        }
        END {
            partial = (rows >= limit && first >= since) ? "yes" : "no"
            printf "%d\t%d\t%d\t%s\t%s\t%s\t%s\n", count["allowed"], count["denied"], count["failed"],
                (list["allowed"] == "" ? "-" : list["allowed"]), (list["denied"] == "" ? "-" : list["denied"]),
                (list["failed"] == "" ? "-" : list["failed"]), partial
        }'
}

# _boxsession_hosts_text <label> <comma-joined hosts>  ->  "Refused: a, b, c and 4 more", or
# nothing for "-".
_boxsession_hosts_text() {
    if [ "$2" = "-" ]; then
        return 0
    fi
    printf '%s\n' "$2" | /usr/bin/awk -F',' -v label="$1" -v shown="$boxsession_line_hosts_shown" '{
        text = label ": "
        for (i = 1; i <= NF && i <= shown; i++) text = text (i > 1 ? ", " : "") $i
        if (NF > shown) text = text " and " (NF - shown) " more"
        print text
    }'
}

# boxsession_prompts <box> <since>  ->  the macOS permission prompts programs in the box met
# since <since>, from agent-vm's exec log, each once, in the order met: what (agent-vm's words:
# "the Downloads folder", "a Keychain item") TAB whether agent-vm stopped the program (true or
# false). Nobody can answer such a prompt inside a box. agent-vm's status on failure, with its
# reason left for agentvm_last_error.
boxsession_prompts() {
    local _rows
    _rows="$(agentvm_execlog "$1" "$boxsession_line_execlog_last")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' -v since="$2" '
        NF == 0 || $1 < since || $5 == "-" { next }
        {
            n = split($5, what, "; ")
            for (i = 1; i <= n; i++) {
                if (what[i] == "" || (what[i] in seen)) continue
                seen[what[i]] = 1
                print what[i] "\t" $6
            }
        }'
}

# _boxsession_prompt_notice <window> <box> <prompts>  ->  0. Tells the user, once per prompt
# and window, that a program in the box met a permission prompt: the lines of boxsession_prompts
# whose prompt is not among those already told, kept tab-joined in aichatv2_boxprompts_<window>.
# Kept by name, not by count: the list is in the order the runs started, so a new prompt of an
# earlier run (the agent's, when another program ran in the box since) lands before prompts
# already told. They are stored before the alert, which waits for OK, so the next refresh does
# not tell them again.
_boxsession_prompt_notice() {
    local _told="$(pb_get "aichatv2_boxprompts_$1")"
    local _new="$(printf '%s\n' "$3" | _told="$_told" /usr/bin/awk -F'\t' '
        BEGIN { n = split(ENVIRON["_told"], list, "\t"); for (i = 1; i <= n; i++) told[list[i]] = 1 }
        NF > 0 && !($1 in told) { told[$1] = 1; print }')"
    if [ -z "$_new" ]; then
        return 0
    fi
    local _names="$(printf '%s\n' "$_new" | /usr/bin/awk -F'\t' '{ text = text (NR > 1 ? "\t" : "") $1 } END { print text }')"
    pb_set "aichatv2_boxprompts_$1" "$_told${_told:+$boxsession_tab}$_names"
    local _what="$(printf '%s\n' "$_new" | /usr/bin/awk -F'\t' '{ text = text (NR > 1 ? ", " : "") $1 } END { print text }')"
    local _stopped="$(printf '%s\n' "$_new" | /usr/bin/awk -F'\t' '$2 == "true" { s = 1 } END { print (s ? "yes" : "no") }')"
    local _boxes
    _boxes="$(agentvm_boxes)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        agentvm_last_error "$_status" >/dev/null
        _boxes=""
    fi
    local _image="$(printf '%s\n' "$_boxes" | /usr/bin/awk -F'\t' -v box="$2" '$1 == box { print $3; exit }')"
    local _outcome
    if [ "$_stopped" = "yes" ]; then
        _outcome="Nobody can answer that prompt inside the box, so agent-vm stopped the program. The agent may report that a command failed."
    else
        _outcome="Nobody can answer that prompt inside the box, so the program may wait until it is answered on the box's screen (Tools > AgentVM, Boxes, View and Control)."
    fi
    # Found by the quiet watch (boxsession_watch): a program left waiting on the prompt may be why
    # the turn stalled. One that agent-vm stopped is not what the agent waits for.
    case "$_stopped:$boxsession_line_quiet" in
        yes:*) ;;
        *:|*:*[!0123456789]*) ;;
        *)
            if [ "$boxsession_line_quiet" -lt 90 ]; then
                _outcome="$_outcome The agent has added nothing to the conversation for $boxsession_line_quiet seconds, and this may be why."
            else
                _outcome="$_outcome The agent has added nothing to the conversation for about $(( (boxsession_line_quiet + 30) / 60 )) minutes, and this may be why."
            fi ;;
    esac
    # The advice agent-vm itself gives: a Keychain dialog is avoided by logging in with the program
    # inside the box, so the item is its own; any other prompt by Full Disk Access for the image.
    local _kinds="$(printf '%s\n' "$_new" | /usr/bin/awk -F'\t' '$1 == "a Keychain item" { k = 1; next } { o = 1 } END { print (k ? "k" : "") (o ? "o" : "") }')"
    local _fix=""
    case "$_kinds" in
        *o*)
            if [ -n "$_image" ] && [ "$_image" != "-" ]; then
                _fix="To let programs in boxes use protected folders, give the image $_image Full Disk Access: Tools > AgentVM, Images, then the Full Disk Access... button. A box made before that keeps the access it had."
            else
                _fix="To let programs in boxes use protected folders, give the box's image Full Disk Access: Tools > AgentVM, Images, then the Full Disk Access... button. A box made before that keeps the access it had."
            fi ;;
    esac
    case "$_kinds" in
        *k*)
            _fix="${_fix}${_fix:+

}A Keychain item belongs to the program that made it. Log in with the agent inside a kept box (Select ACP Agent, Keys..., then Log in inside the AgentVM box), so the item is its own and nobody is asked." ;;
    esac
    "$alert" --level caution --title "$APPLET_NAME" --ok "OK" \
        "A program in AgentVM box $2 needed macOS permission to use $_what.

$_outcome

$_fix"
    return 0
}

# boxsession_line_refresh <window>  ->  0. Restates the line from the box's network log, the
# permission prompts its programs met from its exec log, telling the user of a new prompt once,
# and what the project changed since its snapshot, when the window has one. Nothing for a window
# without a line. A network log that cannot be read says so on the line, with agent-vm's reason in
# the tooltip; an exec log that cannot be read adds nothing.
boxsession_line_refresh() {
    local _stamp="$(pb_get "aichatv2_boxline_$1")"
    if [ -z "$_stamp" ]; then
        return 0
    fi
    pb_set "aichatv2_boxline_at_$1" "$(/bin/date +%s)"
    local _box="${_stamp%%"$boxsession_tab"*}"
    local _rest="${_stamp#*"$boxsession_tab"}"
    local _since="${_rest%%"$boxsession_tab"*}"
    local _head="${_rest#*"$boxsession_tab"}"
    local _tail _help
    local _counts
    _counts="$(boxsession_net_counts "$_box" "$_since")"
    local _status=$?
    if [ "$_status" -ne 0 ] || [ -z "$_counts" ]; then
        _tail="network log unavailable"
        _help="$(agentvm_last_error "$_status")"
    else
        _boxsession_net_text "$_box" "$_counts"
    fi
    local _prompts
    _prompts="$(boxsession_prompts "$_box" "$_since")"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        agentvm_last_error "$_status" >/dev/null
        _prompts=""
    fi
    local _prompt_count="$(printf '%s\n' "$_prompts" | /usr/bin/awk 'NF > 0 { n++ } END { print n + 0 }')"
    if [ "$_prompt_count" = "1" ]; then
        _tail="$_tail - 1 permission prompt"
    elif [ "$_prompt_count" != "0" ]; then
        _tail="$_tail - $_prompt_count permission prompts"
    fi
    if [ "$_prompt_count" != "0" ]; then
        _help="Permission prompts nobody in the AgentVM box could answer: $(printf '%s\n' "$_prompts" | /usr/bin/awk -F'\t' 'NF > 0 { text = text (text == "" ? "" : ", ") $1 } END { print text }')$boxsession_newline$_help"
    fi
    # What the project changed since its snapshot, when the window has one (aichat.snapshot.library.sh).
    local _snap_text _snap_help
    _snapshot_changes_text "$1"
    if [ $? -eq 0 ]; then
        _tail="$_tail - $_snap_text"
        _help="$_help$boxsession_newline$_snap_help"
    fi
    local _kept="$(_boxsession_kept_note "$1")"
    if [ -n "$_kept" ]; then
        _help="$_help$boxsession_newline$_kept"
    fi
    "$dialog" "$1" "$boxsession_line_id" "$_head - $_tail"
    "$dialog" "$1" "$boxsession_line_id" omc_set_property help "$_help"
    if [ "$_prompt_count" != "0" ]; then
        _boxsession_prompt_notice "$1" "$_box" "$_prompts"
    fi
    return 0
}

# boxsession_line_focus_gap: seconds a window's line stays fresh enough that coming to the front
# does not refresh it again.
boxsession_line_focus_gap=10

# boxsession_line_focus <window>  ->  0. The window came to the front: its line is refreshed, so
# hosts reached or refused while it was behind other windows (a long turn, a program the agent left
# running) show without waiting for the next message. Not when the line was refreshed less than
# boxsession_line_focus_gap seconds ago: switching between windows would otherwise read agent-vm's
# logs on every click, and each refresh that overlaps another could tell of a new permission
# prompt twice. Nothing for a window without a line.
boxsession_line_focus() {
    local _stamp="$(pb_get "aichatv2_boxline_$1")"
    if [ -z "$_stamp" ]; then
        return 0
    fi
    local _at="$(pb_get "aichatv2_boxline_at_$1")"
    local _now="$(/bin/date +%s)"
    case "$_at" in
        ''|*[!0123456789]*) ;;
        *)
            if [ $((_now - _at)) -lt "$boxsession_line_focus_gap" ]; then
                return 0
            fi ;;
    esac
    boxsession_line_refresh "$1"
}

# THE QUIET WATCH. Nothing tells Cadabra that a turn runs or has stalled: the chat element sends
# the prompt and streams the reply itself, and aichat.chat.entry.sh sees only finalized entries
# (messages, thoughts, tool calls). A turn that goes quiet may be a program in the box waiting on a
# macOS permission prompt that nobody can answer there, which the line would tell only after the
# next message. So every finalized entry of a box window marks the time (boxsession_watch_mark),
# and one watch per window (boxsession_watch) refreshes the line once the conversation has been
# quiet for boxsession_watch_quiet seconds, and again each time the quiet doubles, until
# boxsession_watch_for seconds after the last entry: with the defaults at 30 seconds, then 1, 2,
# 4 and 8 minutes. A prompt found then is told with a sentence saying it may be why the agent has
# gone quiet (boxsession_line_quiet). The watch holds aichatv2_boxwatch_<window> (its pid) and
# ends when another watch took the key, when the line is gone (the window released its box), or
# when the time is up. CADABRA_BOXWATCH_EVERY, _QUIET and _FOR are test seams, in seconds.
boxsession_watch_every="${CADABRA_BOXWATCH_EVERY:-5}"
boxsession_watch_quiet="${CADABRA_BOXWATCH_QUIET:-30}"
boxsession_watch_for="${CADABRA_BOXWATCH_FOR:-600}"
# How long the conversation has been quiet, while the watch refreshes the line; empty otherwise.
boxsession_line_quiet=""

# boxsession_watch_mark_file <window>  ->  the file whose modification time is the window's last
# finalized entry. A file, not a pasteboard key: the entry handler writes it with the shell alone.
boxsession_watch_mark_file() {
    cadabra_run_file "boxwatch.$1"
}

# boxsession_watch_mark <window>  ->  0. A finalized entry: marks the time, and starts the
# window's watch unless one runs.
boxsession_watch_mark() {
    # printf, not ":": a redirection that fails on a special builtin ends a POSIX-mode shell,
    # and with it the entry handler's refresh.
    printf '' 2>/dev/null > "$(boxsession_watch_mark_file "$1")"
    local _pid="$(pb_get "aichatv2_boxwatch_$1")"
    case "$_pid" in
        ''|*[!0123456789]*) ;;
        *)
            # Signal 0 only asks whether that process is there.
            kill -0 "$_pid" 2>/dev/null
            if [ $? -eq 0 ]; then
                return 0
            fi ;;
    esac
    ( boxsession_watch "$1" ) >/dev/null 2>&1 &
    pb_set "aichatv2_boxwatch_$1" "$!"
    return 0
}

# boxsession_watch <window>  ->  0 when it ends (see THE QUIET WATCH). Runs in the background.
boxsession_watch() {
    local _key="aichatv2_boxwatch_$1"
    # This subshell's own pid, which boxsession_watch_mark stored as $!: the parent of a shell
    # that replaces the command substitution's own process.
    local _me="$(exec /bin/sh -c 'echo $PPID')"
    local _mark="$(boxsession_watch_mark_file "$1")"
    # Cadabra's pid. A quit releases the line, but after a crash the line stays on the pasteboard
    # until the next launch, and the watch would read agent-vm's logs and raise alerts for nobody.
    local _app="$(_agentvm_owner_pid)"
    local _holder _line _last _now _quiet _at
    while :; do
        /bin/sleep "$boxsession_watch_every"
        _holder="$(pb_get "$_key")"
        if [ "$_holder" != "$_me" ]; then
            return 0
        fi
        if [ -n "$_app" ]; then
            kill -0 "$_app" 2>/dev/null
            if [ $? -ne 0 ]; then
                break
            fi
        fi
        _line="$(pb_get "aichatv2_boxline_$1")"
        if [ -z "$_line" ]; then
            break
        fi
        _last="$(/usr/bin/stat -f %m "$_mark" 2>/dev/null)"
        case "$_last" in
            ''|*[!0123456789]*) break ;;
        esac
        _now="$(/bin/date +%s)"
        _quiet=$((_now - _last))
        if [ "$_quiet" -ge "$boxsession_watch_for" ]; then
            break
        fi
        if [ "$_quiet" -lt "$boxsession_watch_quiet" ]; then
            continue
        fi
        # Due when the line is at least half as old as the quiet: each refresh doubles the wait.
        _at="$(pb_get "aichatv2_boxline_at_$1")"
        case "$_at" in
            ''|0?*|*[!0123456789]*) _at=0 ;;
        esac
        if [ $(( (_now - _at) * 2 )) -lt "$_quiet" ]; then
            continue
        fi
        boxsession_line_quiet="$_quiet"
        boxsession_line_refresh "$1"
        boxsession_line_quiet=""
    done
    _holder="$(pb_get "$_key")"
    [ "$_holder" = "$_me" ] && pb_set "$_key" ""
    return 0
}

# _boxsession_net_text <box> <boxsession_net_counts row>  ->  sets _tail and _help, the caller's
# locals, to the network part of the line and its tooltip.
_boxsession_net_text() {
    local _reached _refused _failed _reached_hosts _refused_hosts _failed_hosts _partial
    IFS="$boxsession_tab" read -r _reached _refused _failed _reached_hosts _refused_hosts _failed_hosts _partial <<EOF
$2
EOF
    if [ "$_reached" = "0" ] && [ "$_refused" = "0" ] && [ "$_failed" = "0" ]; then
        _tail="no connections yet"
    elif [ "$_reached" = "0" ]; then
        _tail="no host reached"
    elif [ "$_reached" = "1" ]; then
        _tail="1 host reached"
    else
        _tail="$_reached hosts reached"
    fi
    if [ "$_refused" != "0" ]; then
        _tail="$_tail, $_refused refused"
    fi
    if [ "$_failed" != "0" ]; then
        _tail="$_tail, $_failed failed"
    fi
    _help=""
    local _part _line
    for _part in "Reached|$_reached_hosts" "Refused|$_refused_hosts" "Failed|$_failed_hosts"; do
        _line="$(_boxsession_hosts_text "${_part%%|*}" "${_part#*|}")"
        if [ -n "$_line" ]; then
            _help="$_help$_line$boxsession_newline"
        fi
    done
    _help="${_help}Counted for every program in AgentVM box $1 since the agent started, each connection when it opens"
    if [ "$_partial" = "yes" ]; then
        _help="$_help, over its last $boxsession_line_netlog_last connections"
    fi
    _help="$_help. Programs in the box reach only the hosts its rules allow; agent-vm box netlog $1 --denied lists the refused ones."
}

# boxsession_box_users <box>  ->  how many rows name the box.
boxsession_box_users() {
    boxsession_registry_rows | /usr/bin/awk -F'\t' -v box="$1" '$2 == box { n++ } END { print n + 0 }'
}

# boxsession_disposable_name <agent id>  ->  a new box name, "cadabra-<agent>-<6 hex digits>".
# The agent part keeps what agent-vm allows in a name (lower-case letters, digits, ".", "_",
# "-"), with anything else as "-" ("custom:3" becomes "custom-3"), at most 40 characters.
boxsession_disposable_name() {
    local _slug="$(printf '%s' "$1" | /usr/bin/tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' \
        | /usr/bin/tr -c 'abcdefghijklmnopqrstuvwxyz0123456789._-' '-' | /usr/bin/cut -c1-40)"
    local _hex="$(/usr/bin/od -An -N3 -tx1 /dev/urandom | /usr/bin/tr -d ' \n')"
    printf 'cadabra-%s-%s\n' "${_slug:-agent}" "$_hex"
}

# boxsession_start <window> <run-in> <agent id> <project> <yes|no read-only> [<use tools>]
#   ->  the box name, once the box runs and the project is shared in it. For "new:<image>" the
# box is made first, with the catalog's network rules for the agent (none for an agent the
# catalog does not know: the allowlist then allows nothing), the hosts saved for it, and, with
# <use tools> true, the rules of the box pane's servers (boxsession_tools_rules), which a kept
# box gets added. "readonly" adds none: the search server, the one that needs them, has gated
# tools and is never handed over in that mode. The window's registry row is written as soon as the box
# is known, so the caller releases it on failure exactly as on a window close. A failure's
# message is left for agentvm_last_error.
boxsession_start() {
    if [ $# -ne 5 ] && [ $# -ne 6 ]; then
        _agentvm_refuse 2 "boxsession_start needs a window, where the agent runs, its id, a project, yes or no, and optionally the tools setting."
        return 2
    fi
    local _window="$1" _run_in="$2" _agent="$3" _project="$4" _read_only="$5" _use_tools="${6:-false}"
    # Cadabra's tools for the agent (Use Tools on) need the box pane's rules too (Internet).
    local _tool_rules=""
    case "$_use_tools" in
        true) _tool_rules="$(boxsession_tools_rules)" ;;
    esac
    local _rules=""
    case "$_run_in" in
        new:?*)
            _rules="$("$agentvm_python" "$boxsession_catalog_py" box-list "$_agent" allow 2>"$agentvm_err_file")"
            local _status=$?
            if [ "$_status" -ne 0 ]; then
                _agentvm_refuse 1 "The agent catalog could not be read: $(/bin/cat "$agentvm_err_file" 2>/dev/null)"
                return 1
            fi
            # The hosts the user allowed for this agent in earlier boxes (Allow for <agent>),
            # after the catalog's; a rule in both is passed once.
            _rules="$(printf '%s\n%s\n%s\n' "$_rules" "$(acp_agent_allowed "$_agent")" "$_tool_rules" | /usr/bin/awk 'NF && !seen[$0]++')" ;;
    esac
    _boxsession_start_box "$_window" "$_run_in" "$_agent" "$_project" "$_read_only" "$_rules" "$_tool_rules"
}

# _boxsession_start_box <window> <run-in> <name part> <project> <yes|no read-only> <rules>
#   [<kept rules>]  ->  boxsession_start's work for any kind of session: the box name once it
# runs with the project shared. <name part> goes into a disposable box's name
# (boxsession_disposable_name); <rules> are its network rules, one per line (a rule never holds
# whitespace), used only when the box is made here. <kept rules> are the rules Cadabra's tools
# need (boxsession_tools_rules), added to a kept box: on an allowlist they are added (never
# removed: a kept box's rules are its own); an open box reaches every host already; one whose
# network is off is refused, since Internet would be on in a box that reaches nothing. A box
# whose record has no network runs open (agent-vm's legacy boxes); one whose mode cannot be read
# gets the rules added, as before this was checked.
_boxsession_start_box() {
    local _window="$1" _run_in="$2" _slug="$3" _project="$4" _read_only="$5" _rules="$6" _kept_rules="${7:-}"
    case "$_project" in
        /*) ;;
        *) _agentvm_refuse 2 "The project must be an absolute path, not \"$_project\"."
           return $? ;;
    esac
    # Checked before a disposable box is made for nothing: the warm-up would refuse it only
    # after the box had been made and booted.
    case "$_read_only" in
        yes|no) ;;
        *) _agentvm_refuse 2 "read-only must be yes or no, not \"$_read_only\"."
           return $? ;;
    esac
    # A window starting again (another agent, say) gives up its earlier box first, or a
    # disposable one would be left running with no row to release it.
    boxsession_release "$_window"
    local _box _disposable
    case "$_run_in" in
        box:?*)
            _box="${_run_in#box:}"
            _disposable=no
            _agentvm_need_name box "$_box" || return $?
            if [ -n "$_kept_rules" ]; then
                local _mode="$(agentvm_boxes 2>/dev/null | /usr/bin/awk -F'\t' -v box="$_box" '$1 == box { print $17; exit }')"
                /bin/rm -f "$agentvm_err_file"
                case "$_mode" in
                    off)
                        _agentvm_refuse 1 "The kept AgentVM box $_box has its network off, so Internet search & fetch cannot work in it. Turn Internet off in Agentic Session Tools, or give the box a network in Tools > AgentVM."
                        return 1 ;;
                    open|-) _kept_rules="" ;;
                esac
            fi ;;
        new:?*)
            local _image="${_run_in#new:}"
            _agentvm_need_name image "$_image" || return $?
            _box="$(boxsession_disposable_name "$_slug")"
            _disposable=yes
            # The rules become the positional parameters, one per line. A here-document rather
            # than a pipe, so the loop runs in this shell and its `set` stays.
            set --
            local _rule
            while IFS= read -r _rule; do
                if [ -n "$_rule" ]; then
                    set -- "$@" "$_rule"
                fi
            done <<EOF
$_rules
EOF
            agentvm_box_create "$_box" "$_image" "" "" allowlist yes "$@" || return $? ;;
        *)
            _agentvm_refuse 2 "\"$_run_in\" is not an AgentVM box choice: box:<name> or new:<image>."
            return 2 ;;
    esac
    boxsession_registry_add "$_window" "$_box" "$_disposable" "$_project" "$_read_only" || return $?
    agentvm_box_start "$_box" || return $?
    if [ "$_disposable" = "no" ]; then
        local _rule
        for _rule in $_kept_rules; do
            agentvm_box_allow "$_box" "$_rule" || return $?
        done
    fi
    agentvm_box_warmup "$_box" "$_project" "$_read_only" || return $?
    printf '%s\n' "$_box"
}

# TOOLS IN A BOX. A local model's MCP servers (replay, pdfutil, time-mcp and the Python search
# server) can run in a box while the model runs on this Mac: mlx-agent starts each server as
# `agent-vm exec --box B --project P -- <server>` (generate_mcp_configs.py's box mode). The
# servers are Cadabra's own files, so they are copied into the box user's
#   ~/Library/Application Support/Cadabra/Tools/<version>-<digest>/
# in the same layout as in Cadabra.app/Contents, once per box and Cadabra build: a tar stream from
# this Mac into `tar -x` in the box (about 80 MB, under 2 s), then a bytecode compile of the
# Python files into ~/Library/Caches/Cadabra/pycache there (about 2 s), which each server's first
# start would otherwise pay. A marker file written last says a copy is complete; copies of other
# builds are removed when a new one lands. A copy rather than a shared folder: the box has one
# shared folder, the project's, and Python's many small files are slow over it.
#
# The copy includes replay-box-sandbox.json, replay's own Seatbelt profile inside the box, used
# only when the Local server is set to confine itself there (mcp_box_setting confineLocal; off by
# default, the box being the boundary): the project stays read-write through --allow-write, the
# box's temporary folders are writable, and the toolchains and /private/etc/ssl are readable
# (curl needs its certificates), so a shell command the model runs cannot change the box user's
# home folder, where a kept box keeps logins.
#
# The digest covers the copied files' paths, sizes and modification times (under 0.1 s), so a
# rebuilt Cadabra copies again even at the same version.
boxsession_tools_items="Support/replay Support/pdfutil Support/time-mcp Library/Python Library/Packages Resources/replay-box-sandbox.json"
# The rule the search server needs: agent-vm's "public" (any public host name, logged, never
# this Mac or the local network), since its fetch tool reads whatever page the model names.
boxsession_tools_internet_rule="public"
# How long a window waits, in tenths of a second, for another window's copy into the same box,
# and after how many seconds a copy's lock counts as left over from a killed handler. A copy
# takes 3-5 s, so a minute is ample, and it is well inside the wait (about two minutes with the
# tools each try runs), so a window finding a killed handler's lock takes it over instead of
# giving up. CADABRA_BOXTOOLS_LOCK_WAIT is a test seam.
boxsession_tools_lock_wait="${CADABRA_BOXTOOLS_LOCK_WAIT:-1200}"
boxsession_tools_lock_stale=60

# boxsession_tools_id  ->  "<Cadabra version>-<12 hex digits>", the copy's folder name.
boxsession_tools_id() {
    local _contents="$OMC_APP_BUNDLE_PATH/Contents"
    # Cadabra's Info.plist has CFBundleVersion only.
    local _version="$("$plister" get string "$_contents/Info.plist" /CFBundleVersion 2>/dev/null)"
    set --
    local _item
    for _item in $boxsession_tools_items; do
        set -- "$@" "$_contents/$_item"
    done
    # Paths relative to Contents, so moving Cadabra.app copies nothing again.
    local _digest="$(/usr/bin/find "$@" -type f -exec /usr/bin/stat -f '%N %z %m' {} + 2>/dev/null \
        | _contents="$_contents/" /usr/bin/awk '{ if (index($0, ENVIRON["_contents"]) == 1) $0 = substr($0, length(ENVIRON["_contents"]) + 1); print }' \
        | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-12)"
    printf '%s-%s\n' "${_version:-0}" "$_digest"
}

# _boxsession_tools_lock <box> / _boxsession_tools_unlock <box> - one copy into a box at a time,
# across Cadabra's windows (a directory; mkdir is atomic). Waits for another window's copy; a
# lock older than boxsession_tools_lock_stale seconds is taken over. 1 when the wait ran out.
_boxsession_tools_lock() {
    local _lock="$mcp_app_support/box-tools-$1.lock"
    local _left="$boxsession_tools_lock_wait" _made _mtime _now
    /bin/mkdir -p "$mcp_app_support" 2>/dev/null
    while [ "$_left" -gt 0 ]; do
        /bin/mkdir "$_lock" 2>/dev/null
        _made=$?
        if [ "$_made" -eq 0 ]; then
            return 0
        fi
        _left=$((_left - 1))
        _mtime="$(/usr/bin/stat -f%m "$_lock" 2>/dev/null)"
        _now="$(/bin/date +%s)"
        if [ -n "$_mtime" ] && [ $((_now - _mtime)) -gt "$boxsession_tools_lock_stale" ]; then
            /bin/mv "$_lock" "$_lock.stale.$$" 2>/dev/null
            /bin/rm -rf "$_lock.stale.$$"
            continue
        fi
        /bin/sleep 0.1
    done
    return 1
}

_boxsession_tools_unlock() {
    /bin/rmdir "$mcp_app_support/box-tools-$1.lock" 2>/dev/null
}

# The two programs run in the box by /bin/sh. The first says whether the copy <id> is complete
# and where it and the bytecode cache are; the second, reading the tar stream on its standard
# input, puts a copy there, checks that each item arrived, compiles it, removes copies of other
# builds with their bytecode, and marks it complete.
# A failed compile costs only speed, so it is not an error.
_boxsession_tools_where='dir="$HOME/Library/Application Support/Cadabra/Tools/$1"
state=missing
if [ -f "$dir/.cadabra-tools-complete" ]; then state=ready; fi
printf "%s\t%s\t%s\n" "$state" "$dir" "$HOME/Library/Caches/Cadabra/pycache"'
_boxsession_tools_install='dir="$1"; cache="$2"; base="${dir%/*}"
shift 2
/bin/rm -rf "$dir" || exit 1
/bin/mkdir -p "$dir" || exit 1
/usr/bin/tar -xf - -C "$dir" || exit 1
for item in "$@"; do
    if [ ! -e "$dir/$item" ]; then printf "Error: %s did not arrive in the box.\n" "$item" >&2; exit 1; fi
done
PYTHONPYCACHEPREFIX="$cache" "$dir/Library/Python/bin/python3" -m compileall -q "$dir/Library/Packages" "$dir/Library/Python/lib" >/dev/null 2>&1
for old in "$base"/*; do
    if [ "$old" != "$dir" ]; then /bin/rm -rf "$old" "$cache$old"; fi
done
: > "$dir/.cadabra-tools-complete" || exit 1'

# boxsession_tools_copy <box>  ->  one row, the copy's folder in the box TAB the bytecode cache
# folder there, once Cadabra's tools are in the running box (copied now, or found from before).
# A failure's message is left for agentvm_last_error.
boxsession_tools_copy() {
    _agentvm_need_name box "$1" || return $?
    local _box="$1"
    local _contents="$OMC_APP_BUNDLE_PATH/Contents"
    local _item
    for _item in $boxsession_tools_items; do
        if [ ! -e "$_contents/$_item" ]; then
            _agentvm_refuse 1 "Cadabra's tools cannot be copied into the AgentVM box: $_item is missing from Cadabra.app."
            return 1
        fi
    done
    local _id="$(boxsession_tools_id)"
    _boxsession_tools_lock "$_box"
    local _locked=$?
    if [ "$_locked" -ne 0 ]; then
        _agentvm_refuse 1 "Another Cadabra window is still copying Cadabra's tools into the AgentVM box $_box. Try again in a minute."
        return 1
    fi
    local _where
    _where="$(agentvm_box_exec "$_box" /bin/sh -c "$_boxsession_tools_where" sh "$_id" </dev/null)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        _boxsession_tools_unlock "$_box"
        return "$_status"
    fi
    local _state _dir _cache
    IFS="$boxsession_tab" read -r _state _dir _cache <<EOF
$_where
EOF
    case "$_state:$_dir:$_cache" in
        ready:/?*:/?*|missing:/?*:/?*) ;;
        *)
            _boxsession_tools_unlock "$_box"
            _agentvm_refuse 1 "The AgentVM box $_box did not say where Cadabra's tools go (it answered \"$_where\")."
            return 1 ;;
    esac
    if [ "$_state" = "missing" ]; then
        set --
        for _item in $boxsession_tools_items; do
            set -- "$@" "$_item"
        done
        # The items follow as the script's arguments: the box's tar takes an empty stream (a tar
        # here that could not run) as an empty archive, so the script checks that each arrived.
        /usr/bin/tar -cf - -C "$_contents" "$@" 2>/dev/null \
            | agentvm_box_exec "$_box" /bin/sh -c "$_boxsession_tools_install" sh "$_dir" "$_cache" "$@"
        _status=$?
        if [ "$_status" -ne 0 ]; then
            _boxsession_tools_unlock "$_box"
            local _why="$(agentvm_last_error "$_status")"
            _agentvm_refuse "$_status" "Cadabra's tools could not be copied into the AgentVM box $_box: $_why"
            return "$_status"
        fi
    fi
    _boxsession_tools_unlock "$_box"
    printf '%s\t%s\n' "$_dir" "$_cache"
}

# boxsession_tools_rules  ->  the network rules a box needs for the box pane's servers, one per
# line: any public host with Internet on (the search server), else none. The time server needs
# none (the box's clock follows this Mac's), nor do the others.
boxsession_tools_rules() {
    local _internet="$(mcp_box_setting internet)"
    if [ "$_internet" = "true" ]; then
        printf '%s\n' "$boxsession_tools_internet_rule"
    fi
}

# boxsession_start_tools <window> <run-in> <project> <yes|no read-only>  ->  the box name once
# the box runs, the project is shared in it and Cadabra's tools are copied there, with the
# window's tools record set (mcp_box_tools_set) for generate_mcp_configs.py's box mode. A new
# disposable box is named cadabra-tools-<6 hex digits> and gets the rules of the box pane's
# servers (boxsession_tools_rules). A kept box on an allowlist gets them added (never removed:
# a kept box's rules are its own); an open one reaches every host already; one whose network is
# off is refused when rules are needed, before it starts, since Internet would be on in a box
# that reaches nothing. A box whose record has no network runs open (agent-vm's legacy boxes).
# The window's registry row is written as soon as the box is known, like boxsession_start's.
# A failure's message is left for agentvm_last_error.
boxsession_start_tools() {
    if [ $# -ne 4 ]; then
        _agentvm_refuse 2 "boxsession_start_tools needs a window, where the tools run, a project and yes or no."
        return 2
    fi
    local _window="$1" _run_in="$2" _project="$3" _read_only="$4"
    local _box
    local _rules="$(boxsession_tools_rules)"
    _box="$(_boxsession_start_box "$_window" "$_run_in" tools "$_project" "$_read_only" "$_rules" "$_rules")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    local _copy
    _copy="$(boxsession_tools_copy "$_box")"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    mcp_box_tools_set "$_window" "$_box" "$_project" "$_read_only" "${_copy%%"$boxsession_tab"*}" "${_copy#*"$boxsession_tab"}"
    # Read back: without the record the transport would build a config for this Mac.
    local _record="$(mcp_box_tools_get "$_window")"
    if [ "${_record%%"$boxsession_tab"*}" != "$_box" ]; then
        _agentvm_refuse 1 "Cadabra could not remember that this window's tools run in the AgentVM box $_box."
        return 1
    fi
    printf '%s\n' "$_box"
}

# boxsession_secret <agent id>  ->  the variable name of the key chosen for the agent in the Keys
# window (acp_agent_secret), or nothing when none is chosen; status 1, with the reason left for
# agentvm_last_error, when the choice cannot be honored: it cannot be read, the agent does not use
# that key (the catalog's box-keys), or the Keychain does not hold it. Refused rather than
# dropped: the agent would start without its key and fail in its own words, or not at all.
# A key agent-vm cannot read without macOS asking is still passed: the dialog is the user's to
# answer.
boxsession_secret() {
    local _chosen="$(acp_agent_secret "$1")"
    if [ "$_chosen" = "none" ]; then
        return 0
    fi
    if [ "$_chosen" = "damaged" ] || ! acp_agent_valid_secret_name "$_chosen"; then
        _agentvm_refuse 1 "The key chosen for this agent cannot be read from Cadabra's settings. Choose it again with Keys... in Select ACP Agent."
        return 1
    fi
    local _label
    _label="$("$agentvm_python" "$boxsession_catalog_py" box-keys "$1" 2>/dev/null \
        | /usr/bin/awk -F'\t' -v name="$_chosen" '$1 == name { print $2; exit }')"
    if [ -z "$_label" ]; then
        _agentvm_refuse 1 "This agent does not use the key $_chosen. Choose another with Keys... in Select ACP Agent."
        return 1
    fi
    if [ "$_label" = "-" ]; then
        _label="$_chosen"
    fi
    local _kept
    _kept="$(agentvm_secrets)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        _agentvm_refuse 1 "Could not read which keys AgentVM keeps: $(agentvm_last_error "$_status")"
        return 1
    fi
    local _found="$(printf '%s\n' "$_kept" | /usr/bin/awk -F'\t' -v name="$_chosen" '$1 == name { print "yes"; exit }')"
    if [ -z "$_found" ]; then
        _agentvm_refuse 1 "The key chosen for this agent, $_label ($_chosen), is not in the Keychain. Store it with Keys... in Select ACP Agent."
        return 1
    fi
    printf '%s\n' "$_chosen"
    return 0
}

# boxsession_transport <command> <window> <agent id> <box> <project> <yes|no read-only> <level>
#   [<use tools>]  ->  the Chat element's transport JSON for the agent in the box, or nothing and
# status 1 with the reason left for agentvm_last_error. <agent id> is "" for a command the user
# edited: the command then runs as typed, with no catalog recipe and no secret. <level> is free,
# ask or plan. <use tools> (true, readonly or false, the default) hands the agent Cadabra's MCP
# servers: they are copied into the box (boxsession_tools_copy) and listed as the agent starts
# them there, at their box paths (generate_mcp_configs.py --client in-box, following the box
# pane's settings); "readonly" passes only the servers with no permission-gated tools.
# The builder is called directly, never through aichat_acp_transport_json, whose fallback builds
# a transport of its own when the builder prints nothing: here that would run the agent on this
# Mac instead of refusing.
boxsession_transport() {
    if [ $# -ne 7 ] && [ $# -ne 8 ]; then
        _agentvm_refuse 2 "boxsession_transport needs a command, a window, an agent id, a box, a project, yes or no, a level and optionally the tools setting."
        return 2
    fi
    local _command="$1" _window="$2" _agent="$3" _box="$4" _project="$5" _read_only="$6" _level="$7"
    local _use_tools="${8:-false}"
    local _cfg="$(aichat_session_config_dir "$_window")/mcp-config.json"
    # A config left by an earlier launch of the window must never reach this agent.
    /bin/rm -f "$_cfg"
    case "$_use_tools" in
        true|readonly)
            local _copy
            _copy="$(boxsession_tools_copy "$_box")"
            local _copy_status=$?
            if [ "$_copy_status" -ne 0 ]; then
                return 1
            fi
            set -- --box "$_box" --agent-vm "$(agentvm_bin)" --project "$_project" \
                --guest-tools "${_copy%%"$boxsession_tab"*}" --guest-pycache "${_copy#*"$boxsession_tab"}" --client in-box
            local _store="$(agentvm_setting agent-vm-home)"
            if [ -n "$_store" ]; then
                set -- "$@" --agent-vm-home "$_store"
            fi
            if [ "$_read_only" = "yes" ]; then
                set -- "$@" --read-only
            fi
            # Its diagnostics (a server omitted, a failed probe) go to the log; stdout stays the JSON.
            generate_stdio_mcp_config "$_cfg" "$@" 1>&2
            ;;
        *) _use_tools=false ;;
    esac
    set -- --box "$_box" --agent-vm "$(agentvm_bin)" --project "$_project" --level "$_level"
    local _home="$(agentvm_setting agent-vm-home)"
    if [ -n "$_home" ]; then
        set -- "$@" --agent-vm-home "$_home"
    fi
    if [ "$_read_only" = "yes" ]; then
        set -- "$@" --read-only
    fi
    if [ -n "$_agent" ]; then
        set -- "$@" --agent-id "$_agent"
        local _secret
        _secret="$(boxsession_secret "$_agent")"
        local _secret_status=$?
        if [ "$_secret_status" -ne 0 ]; then
            return 1
        fi
        if [ -n "$_secret" ]; then
            set -- "$@" --secret "$_secret"
        fi
    fi
    local _json
    _json="$("$agentvm_python" "$boxsession_transport_py" /usr/bin/false external "$_command" "$_cfg" "$_project" "$_use_tools" "$@" 2>"$agentvm_err_file")"
    if [ -z "$_json" ]; then
        local _why="$(/usr/bin/sed 's/^acp_transport_json: //' "$agentvm_err_file" 2>/dev/null)"
        _agentvm_refuse 1 "${_why:-The transport for the agent could not be built.}"
        return 1
    fi
    /bin/rm -f "$agentvm_err_file"
    printf '%s\n' "$_json"
}

# boxsession_release <window>  ->  0, or 1 when the registry could not be rewritten (the reason
# left for agentvm_last_error). Removes the window's row; when no row names its box any
# more, a disposable box goes (see RELEASE above). Nothing for a window without a row.
boxsession_release() {
    local _row="$(boxsession_registry_row "$1")"
    if [ -z "$_row" ]; then
        return 0
    fi
    _boxsession_rewrite '$1 != ENVIRON["boxsession_window"] { print }' "$1" || return $?
    # The box line has nothing left to count for this window; a refresh started after this finds
    # no stamp and does nothing.
    pb_set "aichatv2_boxline_$1" ""
    pb_set "aichatv2_boxline_at_$1" ""
    pb_set "aichatv2_boxprompts_$1" ""
    pb_set "aichatv2_boxagent_$1" ""
    # A local model's tools no longer run in the box: a later config (an in-place model switch)
    # is made for this Mac.
    mcp_box_tools_clear "$1"
    # The quiet watch finds no line and ends at its next look.
    /bin/rm -f "$(boxsession_watch_mark_file "$1")"
    local _box="$(printf '%s\n' "$_row" | /usr/bin/cut -f2)"
    local _disposable="$(printf '%s\n' "$_row" | /usr/bin/cut -f3)"
    if [ "$_disposable" != "yes" ]; then
        return 0
    fi
    local _users="$(boxsession_box_users "$_box")"
    if [ "$_users" != "0" ]; then
        return 0
    fi
    _boxsession_discard "$_box"
    return 0
}

# _boxsession_discard <disposable box>  ->  deleted when stopped, else a stop job started; a box
# agent-vm no longer knows is already gone. Failures are left for agentvm_last_error: there is
# nobody to show them to at a window close, and the owner lease and box gc are the safety net.
_boxsession_discard() {
    local _status_row
    _status_row="$(agentvm_box_status "$1")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    local _state="$(printf '%s\n' "$_status_row" | /usr/bin/cut -f1)"
    if [ "$_state" = "stopped" ]; then
        agentvm_box_delete "$1"
        return $?
    fi
    agentvm_box_stop_job "$1" >/dev/null
}

# boxsession_close <window>  ->  0, or 1 when the registry could not be rewritten (the reason left
# for agentvm_last_error). A chat window's close: releases its row (boxsession_release), then,
# for a kept box no window uses any more, asks whether to stop it (_boxsession_offer_stop).
boxsession_close() {
    local _row="$(boxsession_registry_row "$1")"
    boxsession_release "$1" || return $?
    if [ -z "$_row" ]; then
        return 0
    fi
    local _box="$(printf '%s\n' "$_row" | /usr/bin/cut -f2)"
    local _disposable="$(printf '%s\n' "$_row" | /usr/bin/cut -f3)"
    if [ "$_disposable" = "yes" ]; then
        return 0
    fi
    local _users="$(boxsession_box_users "$_box")"
    if [ "$_users" != "0" ]; then
        return 0
    fi
    # Windows closing together (Close All) would each find no user left and each ask.
    _boxsession_question_claim "$_box" || return 0
    _boxsession_offer_stop "$_box"
    _boxsession_question_unclaim "$_box"
    return 0
}

# _boxsession_question_claim <box>  ->  0 when this handler may ask about <box>: it made the
# claim, a folder holding its pid, or took over one whose handler is gone. 1 while another
# handler asks. A claim still being written (no pid yet) counts as held.
_boxsession_question_claim() {
    local _dir="$mcp_app_support/box-stop-question-$1"
    /bin/mkdir "$_dir" 2>/dev/null
    if [ $? -ne 0 ]; then
        local _pid="$(/bin/cat "$_dir/pid" 2>/dev/null)"
        case "$_pid" in
            ''|*[!0123456789]*) return 1 ;;
        esac
        kill -0 "$_pid" 2>/dev/null
        if [ $? -eq 0 ]; then
            return 1
        fi
    fi
    printf '%s\n' "$$" > "$_dir/pid"
    return 0
}

# _boxsession_question_unclaim <box>  ->  removes this handler's claim, and only its own.
_boxsession_question_unclaim() {
    local _dir="$mcp_app_support/box-stop-question-$1"
    local _pid="$(/bin/cat "$_dir/pid" 2>/dev/null)"
    if [ "$_pid" = "$$" ]; then
        /bin/rm -rf "$_dir"
    fi
}

# How long, in half seconds, the stop question waits for the closing window's own exec clients to
# end before counting the programs in the box: ChatView ends its agent with SIGTERM, then SIGKILL
# 5 s later.
boxsession_close_wait_steps=14

# _boxsession_own_execs <agent-vm path> <box>  ->  how many exec clients of that agent-vm (the one
# Cadabra runs) serve <box> right now. Once no window uses the box they are the closing window's,
# still ending.
_boxsession_own_execs() {
    local _prefix="$1 exec --box $2 "
    /bin/ps -axo command= 2>/dev/null | _prefix="$_prefix" /usr/bin/awk 'index($0, ENVIRON["_prefix"]) == 1 { n++ } END { print n + 0 }'
}

# _boxsession_offer_stop <kept box>  ->  0. When the box is running or starting, asks whether to
# stop it, saying what it holds, which programs from elsewhere run in it (a Terminal shell, avm,
# another app), and what happens if it is kept; stops it as a job when asked to. With programs
# from elsewhere running, Keep Running is the default button. A box whose status cannot be read
# is left alone: there is no window left to explain it in, and the owner lease stops a box
# Cadabra started when Cadabra exits.
_boxsession_offer_stop() {
    local _own
    local _bin="$(agentvm_bin)"
    local _left="$boxsession_close_wait_steps"
    while :; do
        _own="$(_boxsession_own_execs "$_bin" "$1")"
        if [ "$_own" = "0" ] || [ "$_left" -le 0 ]; then
            break
        fi
        _left=$((_left - 1))
        /bin/sleep 0.5
    done
    local _row
    _row="$(agentvm_box_status "$1")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        agentvm_last_error "$_status" >/dev/null
        return 0
    fi
    local _state="$(printf '%s\n' "$_row" | /usr/bin/cut -f1)"
    case "$_state" in
        running|starting) ;;
        *) return 0 ;;
    esac
    local _execs="$(printf '%s\n' "$_row" | /usr/bin/cut -f8)"
    local _owner="$(printf '%s\n' "$_row" | /usr/bin/cut -f13)"
    local _memory="$(printf '%s\n' "$_row" | /usr/bin/cut -f14)"
    # Programs Cadabra did not start: agent-vm counts every exec and box shell, and the closing
    # window's own clients may not have ended yet.
    local _foreign=0
    case "$_execs" in
        ''|*[!0123456789]*) ;;
        *) _foreign=$((_execs - _own)) ;;
    esac
    if [ "$_foreign" -lt 0 ]; then
        _foreign=0
    fi
    local _text="No chat window uses it any more."
    case "$_memory" in
        ''|*[!0123456789]*) _text="$_text While it runs it holds one of the two virtual machine slots on this Mac." ;;
        *) _text="$_text While it runs it holds one of the two virtual machine slots on this Mac and $_memory GB of memory." ;;
    esac
    if [ "$_foreign" = "1" ]; then
        _text="$_text

1 program Cadabra did not start runs in it right now (a Terminal shell, avm or another app). Stopping the box ends it."
    elif [ "$_foreign" -gt 1 ]; then
        _text="$_text

$_foreign programs Cadabra did not start run in it right now (a Terminal shell, avm or another app). Stopping the box ends them."
    fi
    local _me="$(_agentvm_owner_pid)"
    if [ -n "$_me" ] && [ "$_owner" = "$_me" ]; then
        _text="$_text

If you keep it running, Cadabra stops it when Cadabra quits."
    else
        _text="$_text

Cadabra did not start it, so it keeps running until it is stopped (Tools > AgentVM)."
    fi
    # The question is about a box no window uses: a window may have started on it during the
    # wait or the status read (the alert is not modal to Cadabra, so also while it is up).
    local _users="$(boxsession_box_users "$1")"
    if [ "$_users" != "0" ]; then
        return 0
    fi
    local _stop=no
    local _answer
    if [ "$_foreign" -gt 0 ]; then
        "$alert" --level caution --title "Stop the AgentVM box $1?" --ok "Keep Running" --other "Stop Box" "$_text"
        _answer=$?
        # Stop Box is the other button (2), not the cancel one, which Escape may choose; an alert
        # that failed (-1) keeps the box.
        if [ "$_answer" -eq 2 ]; then
            _stop=yes
        fi
    else
        "$alert" --level caution --title "Stop the AgentVM box $1?" --ok "Stop Box" --cancel "Keep Running" "$_text"
        _answer=$?
        if [ "$_answer" -eq 0 ]; then
            _stop=yes
        fi
    fi
    if [ "$_stop" != "yes" ]; then
        return 0
    fi
    _users="$(boxsession_box_users "$1")"
    if [ "$_users" != "0" ]; then
        return 0
    fi
    agentvm_box_stop_job "$1" >/dev/null
    _status=$?
    if [ "$_status" -ne 0 ]; then
        "$alert" --level stop --title "Could not stop the AgentVM box $1" --ok "OK" "$(agentvm_last_error "$_status")"
    fi
    return 0
}

# boxsession_release_own  ->  0. At quit: releases every row of this Cadabra process, so its
# disposable boxes go now rather than at the next launch. Their VMs would stop anyway through the
# owner lease; the release also deletes the boxes (or leaves them to box gc, see RELEASE above).
boxsession_release_own() {
    local _me="$(_agentvm_owner_pid)"
    if [ -z "$_me" ]; then
        return 0
    fi
    local _window _box _disposable _project _read_only _pid
    boxsession_registry_rows | while IFS="$boxsession_tab" read -r _window _box _disposable _project _read_only _pid; do
        if [ "$_pid" = "$_me" ]; then
            boxsession_release "$_window"
        fi
    done
    return 0
}

# boxsession_release_stale  ->  0. Releases the rows of Cadabra processes that are gone (a crash
# or force quit): their VMs already stopped through the owner lease, and the rows would
# otherwise keep their boxes counted as in use. A row with no pid ("-") is released too.
boxsession_release_stale() {
    local _window _box _disposable _project _read_only _pid
    boxsession_registry_rows | while IFS="$boxsession_tab" read -r _window _box _disposable _project _read_only _pid; do
        case "$_pid" in
            ''|*[!0123456789]*) ;;
            *) kill -0 "$_pid" 2>/dev/null
               if [ $? -eq 0 ]; then
                   continue
               fi ;;
        esac
        boxsession_release "$_window"
    done
    return 0
}

# The project snapshot, whose changes the box line shows (_snapshot_changes_text). Last, after
# everything here is defined: it sources this file in turn, which then returns at once.
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.snapshot.library.sh"
