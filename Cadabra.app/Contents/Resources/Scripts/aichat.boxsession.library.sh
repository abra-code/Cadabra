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

# _boxsession_lock / _boxsession_unlock - the registry's lock, a directory (mkdir is atomic).
# A lock older than 30 s is left over from a killed handler and is taken over, by renaming it
# away (only one contender's rename succeeds). A waiter gives up after about 10 s and returns 1:
# the caller then leaves the registry alone rather than rewrite it unlocked. Every pass counts
# toward that limit, a takeover too, so a lock that cannot be made (an unwritable folder) ends
# the wait instead of looping; a lock that vanished between mkdir and stat is simply retried.
_boxsession_lock() {
    local _lock="$mcp_app_support/box-sessions.lock"
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
        if [ -n "$_mtime" ] && [ $((_now - _mtime)) -gt 30 ]; then
            /bin/mv "$_lock" "$_lock.stale.$$" 2>/dev/null
            /bin/rm -rf "$_lock.stale.$$"
            continue
        fi
        /bin/sleep 0.1
    done
    return 1
}

_boxsession_unlock() {
    /bin/rmdir "$mcp_app_support/box-sessions.lock" 2>/dev/null
}

# _boxsession_rewrite <awk program> <window> [row]  ->  the registry rewritten through the awk
# program (which prints the rows to keep), under the lock. The program reads the window and the
# row as ENVIRON["boxsession_window"] and ENVIRON["boxsession_row"]: awk -v would turn a "\n"
# or "\t" spelled in a project path into a real line break or tab, past the check for them.
# Status 1, with the reason left for agentvm_last_error, when the lock could not be had or the
# file could not be replaced.
_boxsession_rewrite() {
    local _program="$1" _window="$2" _row="${3:-}"
    local _file="$(boxsession_registry_file)"
    _boxsession_lock
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        _agentvm_refuse 1 "The box session list ($_file) is locked by another Cadabra task, or its folder cannot be written."
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
        _agentvm_refuse 1 "The box session list ($_file) could not be rewritten."
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
                _agentvm_refuse 2 "A tab or a line break cannot be part of a box session's window, box or project."
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

# THE BOX LINE, under the model button of a chat window whose agent runs in a box (a Label put
# into the empty slot 543 of aichat.chat.json, so windows without a box keep their layout):
#   Box s3, project read-only - 4 hosts reached, 2 refused
# Its tooltip names the hosts. The counts cover the connections of every program in the box
# since the agent started, from agent-vm's network log; the chat entry handler refreshes them
# in the background after each message. The window's pasteboard key aichatv2_boxline_<window>
# holds what the refreshes need: box TAB since TAB the line's first part.
# The line's text is set as the Label's value, not with omc_set_property title: a Label shows its
# value, which ActionUI seeds from the title once, at insertion, so a later title change is not
# shown. The tooltip (help) has no such value and is set as a property.
boxsession_line_slot_id=543
boxsession_line_id=544
# How many of the network log's last entries a refresh reads. The log of a kept box grows over
# every session it served (up to 64 MB). agent-vm itself still reads the whole log, but the rows
# converted and counted here stay few; the most _agentvm_need_count accepts.
boxsession_line_netlog_last=999
# How many host names the tooltip lists of each kind.
boxsession_line_hosts_shown=6

# boxsession_line_head <window>  ->  the line's first part, from the registry row and the image
# stamp: "Box s3", "Disposable box cadabra-opencode-3f2a91 from dev-agents", with ", project
# read-only" when so; nothing when the window has no row.
boxsession_line_head() {
    local _fields="$(boxsession_meta_fields "$1")"
    if [ -z "$_fields" ]; then
        return 0
    fi
    printf '%s\n' "$_fields" | /usr/bin/awk -F'\t' '{
        if ($3 == "yes") {
            head = "Disposable box " $1
            if ($2 != "-") head = head " from " $2
        } else {
            head = "Box " $1
        }
        if ($5 == "yes") head = head ", project read-only"
        print head
    }'
}

# boxsession_line_show <window> <box>  ->  puts the line in the window, and remembers the box,
# this moment and the line's first part for the refreshes. Called once the agent's box runs, so
# the connections macOS makes while the box boots are not counted as the agent's.
boxsession_line_show() {
    local _since="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
    local _head="$(boxsession_line_head "$1")"
    if [ -z "$_head" ]; then
        _head="Box $2"
    fi
    pb_set "aichatv2_boxline_$1" "$2$boxsession_tab$_since$boxsession_tab$_head"
    "$dialog" "$1" "$boxsession_line_id" omc_remove_element 2>/dev/null
    "$dialog" "$1" "$boxsession_line_slot_id" omc_insert_element "{\"type\":\"Label\",\"id\":$boxsession_line_id,\"properties\":{\"title\":\"\",\"systemImage\":\"shippingbox\",\"font\":\"footnote\",\"foregroundStyle\":\"secondary\",\"padding\":{\"top\":0,\"leading\":14,\"bottom\":6,\"trailing\":14},\"frame\":{\"maxWidth\":\"infinity\",\"alignment\":\"leading\"}}}"
    "$dialog" "$1" "$boxsession_line_id" "$_head - no connections yet"
    "$dialog" "$1" "$boxsession_line_id" omc_set_property help "Programs in the box reach only the hosts its rules allow. The counts start when the agent does."
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

# boxsession_line_refresh <window>  ->  0. Restates the line from the box's network log. Nothing
# for a window without a line. A log that cannot be read says so on the line, with agent-vm's
# reason in the tooltip.
boxsession_line_refresh() {
    local _stamp="$(pb_get "aichatv2_boxline_$1")"
    if [ -z "$_stamp" ]; then
        return 0
    fi
    local _box="${_stamp%%"$boxsession_tab"*}"
    local _rest="${_stamp#*"$boxsession_tab"}"
    local _since="${_rest%%"$boxsession_tab"*}"
    local _head="${_rest#*"$boxsession_tab"}"
    local _counts
    _counts="$(boxsession_net_counts "$_box" "$_since")"
    local _status=$?
    if [ "$_status" -ne 0 ] || [ -z "$_counts" ]; then
        local _why="$(agentvm_last_error "$_status")"
        "$dialog" "$1" "$boxsession_line_id" "$_head - network log unavailable"
        "$dialog" "$1" "$boxsession_line_id" omc_set_property help "$_why"
        return 0
    fi
    local _reached _refused _failed _reached_hosts _refused_hosts _failed_hosts _partial
    IFS="$boxsession_tab" read -r _reached _refused _failed _reached_hosts _refused_hosts _failed_hosts _partial <<EOF
$_counts
EOF
    local _tail
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
    local _help=""
    local _part _line
    for _part in "Reached|$_reached_hosts" "Refused|$_refused_hosts" "Failed|$_failed_hosts"; do
        _line="$(_boxsession_hosts_text "${_part%%|*}" "${_part#*|}")"
        if [ -n "$_line" ]; then
            _help="$_help$_line$boxsession_newline"
        fi
    done
    _help="${_help}Counted for every program in box $_box since the agent started, as each connection ends (one still open, such as the agent's own to its model provider, is counted when it closes)"
    if [ "$_partial" = "yes" ]; then
        _help="$_help, over its last $boxsession_line_netlog_last connections"
    fi
    _help="$_help. Programs in the box reach only the hosts its rules allow; agent-vm box netlog $_box --denied lists the refused ones."
    "$dialog" "$1" "$boxsession_line_id" "$_head - $_tail"
    "$dialog" "$1" "$boxsession_line_id" omc_set_property help "$_help"
    return 0
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

# boxsession_start <window> <run-in> <agent id> <project> <yes|no read-only>  ->  the box name,
# once the box runs and the project is shared in it. For "new:<image>" the box is made first,
# with the catalog's network rules for the agent (none for an agent the catalog does not know:
# the allowlist then allows nothing). The window's registry row is written as soon as the box
# is known, so the caller releases it on failure exactly as on a window close. A failure's
# message is left for agentvm_last_error.
boxsession_start() {
    if [ $# -ne 5 ]; then
        _agentvm_refuse 2 "boxsession_start needs a window, where the agent runs, its id, a project and yes or no."
        return 2
    fi
    local _window="$1" _run_in="$2" _agent="$3" _project="$4" _read_only="$5"
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
            _agentvm_need_name box "$_box" || return $? ;;
        new:?*)
            local _image="${_run_in#new:}"
            _agentvm_need_name image "$_image" || return $?
            _box="$(boxsession_disposable_name "$_agent")"
            _disposable=yes
            local _rules
            _rules="$("$agentvm_python" "$boxsession_catalog_py" box-list "$_agent" allow 2>"$agentvm_err_file")"
            local _status=$?
            if [ "$_status" -ne 0 ]; then
                _agentvm_refuse 1 "The agent catalog could not be read: $(/bin/cat "$agentvm_err_file" 2>/dev/null)"
                return 1
            fi
            # The rules become the positional parameters, one per line of the catalog's answer
            # (a rule never holds whitespace; acp_catalog.py leaves such values out). A here-
            # document rather than a pipe, so the loop runs in this shell and its `set` stays.
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
            _agentvm_refuse 2 "\"$_run_in\" is not a box choice: box:<name> or new:<image>."
            return 2 ;;
    esac
    boxsession_registry_add "$_window" "$_box" "$_disposable" "$_project" "$_read_only" || return $?
    agentvm_box_start "$_box" || return $?
    agentvm_box_warmup "$_box" "$_project" "$_read_only" || return $?
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
#   ->  the Chat element's transport JSON for the agent in the box, or nothing and status 1 with
# the reason left for agentvm_last_error. <agent id> is "" for a command the user edited: the
# command then runs as typed, with no catalog recipe and no secret. <level> is free, ask or plan.
# The builder is called directly, never through aichat_acp_transport_json, whose fallback builds
# a transport of its own when the builder prints nothing: here that would run the agent on this
# Mac instead of refusing.
boxsession_transport() {
    if [ $# -ne 7 ]; then
        _agentvm_refuse 2 "boxsession_transport needs a command, a window, an agent id, a box, a project, yes or no and a level."
        return 2
    fi
    local _command="$1" _window="$2" _agent="$3" _box="$4" _project="$5" _read_only="$6" _level="$7"
    local _cfg="$(aichat_session_config_dir "$_window")/mcp-config.json"
    # No tools in a box yet, so no server config: drop one left by an earlier launch of the window.
    /bin/rm -f "$_cfg"
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
    _json="$("$agentvm_python" "$boxsession_transport_py" /usr/bin/false external "$_command" "$_cfg" "$_project" false "$@" 2>"$agentvm_err_file")"
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
