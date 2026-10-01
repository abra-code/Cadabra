#!/bin/sh
# aichat.snapshot.library.sh
#
# A chat window's project snapshot: an AgentVM session (`agent-vm session start`), taken before
# the window's agent or tools can touch the project, so what the session changed can be reviewed
# and undone afterwards. For sessions in an AgentVM box and on this Mac alike: agent-vm clones the
# project folder on this Mac (APFS copy-on-write), with no virtual machine.
#
# WHEN. chat_engine_load takes it last before the transport goes to the window (the agent starts
# the moment it lands), after a box started, when Agentic Session Tools' setting for the window's
# place says so (mcp_snapshot_setting: on by default in a box, off on this Mac), for a project
# something in the session can change: not a project shared read-only with a box, and not for a
# local model without tools.
#
# ONE SESSION PER PROJECT. agent-vm keeps one active session per project, so windows on the same
# project share it: a window that finds the project's active session in the registry joins it.
# One that Cadabra did not start (agent-vm or avm in Terminal) is not joined: its undo belongs to
# whoever started it. The start, the lookup and the registry row happen under one lock, so two
# windows starting on one project at once do not take the other's session for a stranger's.
#
# THE REGISTRY, $mcp_app_support/snapshot-sessions.tsv, one row per window with a snapshot:
#   window, session id, project, cadabraPid
# rewritten whole under the box-session registry's lock, as that one is (_boxsession_rewrite_file).
#
# THE END. When no row names a session any more (its last window closed, Cadabra quit, or, at the
# next launch, the Cadabra that started it is gone), the session is ended: its snapshot stays for
# review and undo. A session whose project did not change is discarded at once: there is nothing
# to review. The agent of a closing window gets a few seconds to end, and a change it makes in
# them after that check is not in a discarded session's undo.
#
# THE LINE. A window with a snapshot says what its project changed: on the box line, after the
# network ("- 3 changes, 1 flagged"), or for a window on this Mac on a line of its own in the same
# place ("Project snapshot at 21:38 - 3 changes, 1 flagged"). It is restated after each message
# and when the window comes to the front, as the box line is. Flagged changes are those agent-vm
# marks as able to run code later on this Mac (git hooks, package scripts, build files, symbolic
# links leaving the project); the tooltip names them.
[ -n "${__AICHAT_SNAPSHOT_LIB:-}" ] && return 0
__AICHAT_SNAPSHOT_LIB=1

# The registry lock, the line's element ids and the box line refresh. That library sources this
# one at its end, so either can be sourced first.
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxsession.library.sh"

snapshot_tab="$(printf '\t')"
snapshot_newline="
"
# The line's icon, on a window on this Mac (a box line has its own).
snapshot_line_icon="clock.arrow.circlepath"
# How long a window's line stays fresh enough that coming to the front does not refresh it again,
# as for the box line.
snapshot_line_focus_gap=10

# snapshot_registry_file  ->  the registry's path.
snapshot_registry_file() {
    printf '%s\n' "$mcp_app_support/snapshot-sessions.tsv"
}

# snapshot_registry_rows  ->  the registry's rows (nothing when there is none).
snapshot_registry_rows() {
    local _file="$(snapshot_registry_file)"
    if [ -f "$_file" ]; then
        /bin/cat "$_file"
    fi
}

# snapshot_registry_row <window>  ->  the window's row, or nothing.
snapshot_registry_row() {
    snapshot_registry_rows | snapshot_window="$1" /usr/bin/awk -F'\t' '$1 == ENVIRON["snapshot_window"] { print; exit }'
}

# snapshot_session_users <session id>  ->  how many rows name the session.
snapshot_session_users() {
    snapshot_registry_rows | snapshot_session="$1" /usr/bin/awk -F'\t' '$2 == ENVIRON["snapshot_session"] { n++ } END { print n + 0 }'
}

# snapshot_registry_add <window> <session id> <project>  ->  0, or 1 or 2 with the reason left for
# agentvm_last_error. Replaces the window's row if it has one.
snapshot_registry_add() {
    if [ $# -ne 3 ] || [ -z "$1" ] || [ -z "$3" ]; then
        _agentvm_refuse 2 "snapshot_registry_add needs a window, a session id and a project."
        return 2
    fi
    agentvm_valid_session_id "$2" || { _agentvm_refuse 2 "\"$2\" is not an AgentVM session id."; return 2; }
    local _field
    for _field in "$@"; do
        case "$_field" in
            *"$snapshot_tab"*|*"$snapshot_newline"*)
                _agentvm_refuse 2 "A tab or a line break cannot be part of a snapshot's window or project."
                return 2 ;;
        esac
    done
    local _pid="$(_agentvm_owner_pid)"
    _boxsession_rewrite_file "$(snapshot_registry_file)" \
        '$1 != ENVIRON["boxsession_window"] { print } END { print ENVIRON["boxsession_row"] }' \
        "$1" "$1$snapshot_tab$2$snapshot_tab$3$snapshot_tab${_pid:--}"
}

# snapshot_window_session <window>  ->  the window's session id, or nothing.
snapshot_window_session() {
    local _stamp="$(pb_get "aichatv2_snapshot_$1")"
    printf '%s\n' "${_stamp%%"$snapshot_tab"*}"
}

# _snapshot_project_session <project>  ->  the id of the project's active session, or nothing
# (also when sessions cannot be listed). agent-vm records the project with its links resolved.
_snapshot_project_session() {
    local _resolved="$(cd "$1" 2>/dev/null && /bin/pwd -P)"
    if [ -z "$_resolved" ]; then
        return 0
    fi
    agentvm_sessions 2>/dev/null | snapshot_project="$_resolved" \
        /usr/bin/awk -F'\t' '$2 == "active" && $3 == ENVIRON["snapshot_project"] { print $1; exit }'
    /bin/rm -f "$agentvm_err_file"
}

# snapshot_start <window> <project>  ->  the session id, once the window's row is written: a new
# session, or the one a Cadabra window on the same project already has. Status 3 when the project
# has an active session Cadabra did not start, else agent-vm's status; the reason is left for
# agentvm_last_error either way. A window starting again gives up its earlier snapshot first.
snapshot_start() {
    local _window="$1" _project="$2"
    case "$_project" in
        /*) ;;
        *) _agentvm_refuse 2 "The project must be an absolute path, not \"$_project\"."
           return 2 ;;
    esac
    snapshot_release "$_window"
    # Rows of a Cadabra that crashed are released by the launch in the background; one still there
    # would count as a window using its session, which this one would then join with the crashed
    # run's changes in it. Released here first, outside the lock their release takes.
    snapshot_release_stale
    local _lock="$mcp_app_support/snapshot-start.lock"
    # Held across the clone, which can take long on a huge project: a later window must not take
    # it for one a killed handler left behind (30 s, the registry lock's limit).
    _boxsession_lock "$_lock" 600
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        _agentvm_refuse 1 "Another Cadabra window is taking a snapshot, or $mcp_app_support cannot be written."
        return 1
    fi
    local _row
    _row="$(agentvm_session_start "$_project")"
    _status=$?
    local _id
    if [ "$_status" -eq 0 ]; then
        _id="$(printf '%s\n' "$_row" | /usr/bin/cut -f1)"
    else
        # Kept: the lookup below runs agent-vm again, which would remove the message.
        local _why="$(agentvm_last_error "$_status")"
        _id="$(_snapshot_project_session "$_project")"
        if [ -z "$_id" ]; then
            _boxsession_unlock "$_lock"
            _agentvm_refuse "$_status" "$_why"
            return "$_status"
        fi
        local _users="$(snapshot_session_users "$_id")"
        if [ "$_users" = "0" ]; then
            _boxsession_unlock "$_lock"
            _agentvm_refuse 3 "The project already has an AgentVM session that Cadabra did not start (agent-vm session $_id), and agent-vm keeps one session per project. When whoever started it is done, end it in Terminal with: agent-vm session end $_id"
            return 3
        fi
        _row="$(agentvm_sessions 2>/dev/null | snapshot_session="$_id" /usr/bin/awk -F'\t' '$1 == ENVIRON["snapshot_session"] { print; exit }')"
        /bin/rm -f "$agentvm_err_file"
    fi
    snapshot_registry_add "$_window" "$_id" "$_project"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        # A session made for this window and recorded nowhere would stay active, refusing the
        # project's next snapshot. Its message is the registry's, not this one's. Still under the
        # lock, so no window joins it meanwhile.
        local _users="$(snapshot_session_users "$_id")"
        if [ "$_users" = "0" ]; then
            local _kept="$(/bin/cat "$agentvm_err_file" 2>/dev/null)"
            agentvm_session_discard "$_id" >/dev/null 2>&1
            printf '%s\n' "$_kept" > "$agentvm_err_file"
        fi
        _boxsession_unlock "$_lock"
        return "$_status"
    fi
    _boxsession_unlock "$_lock"
    # The id and when the snapshot was taken (seconds since 1970), for the line.
    local _started="$(printf '%s\n' "$_row" | /usr/bin/cut -f4)"
    pb_set "aichatv2_snapshot_$_window" "$_id$snapshot_tab$_started"
    snapshot_record_meta "$_window"
    printf '%s\n' "$_id"
}

# snapshot_record_meta <window>  ->  0. Adds the window's session to its conversation's record
# (meta.json "snapshots"), once the conversation exists: here for a saved one resumed in the window,
# and by the entry handler when the window's first message makes one.
snapshot_record_meta() {
    local _row="$(snapshot_registry_row "$1")"
    if [ -z "$_row" ]; then
        return 0
    fi
    source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.history.library.sh"
    local _sid="$(pb_get "aichatv2_session_$1")"
    if [ -z "$_sid" ] || [ ! -f "$history_root/$_sid/meta.json" ]; then
        return 0
    fi
    local _id="$(printf '%s\n' "$_row" | /usr/bin/cut -f2)"
    local _project="$(printf '%s\n' "$_row" | /usr/bin/cut -f3)"
    "$history_py" "$history_store" meta-snapshot "$history_root/$_sid" "$_id" "$_project" >/dev/null 2>&1
    return 0
}

# snapshot_release <window>  ->  0, or 1 when the registry could not be rewritten (the reason left
# for agentvm_last_error). Removes the window's row; when no row names its session any more, the
# session ends and, unchanged, is discarded. Nothing for a window without a row.
# The row's removal, the count and the end happen under snapshot_start's lock, as a joining
# window's count and row do: otherwise a window could join the session between this count and its
# end, and be left with a row on an ended (or discarded) session. A lock that cannot be had is
# not waited for further: the window is going, and its session must still end.
snapshot_release() {
    local _row="$(snapshot_registry_row "$1")"
    if [ -z "$_row" ]; then
        return 0
    fi
    local _lock="$mcp_app_support/snapshot-start.lock"
    _boxsession_lock "$_lock" 600
    local _locked=$?
    _boxsession_rewrite_file "$(snapshot_registry_file)" '$1 != ENVIRON["boxsession_window"] { print }' "$1"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        [ "$_locked" -eq 0 ] && _boxsession_unlock "$_lock"
        return "$_status"
    fi
    pb_set "aichatv2_snapshot_$1" ""
    pb_set "aichatv2_snapline_$1" ""
    pb_set "aichatv2_snapline_at_$1" ""
    local _id="$(printf '%s\n' "$_row" | /usr/bin/cut -f2)"
    local _users="$(snapshot_session_users "$_id")"
    if [ "$_users" != "0" ]; then
        [ "$_locked" -eq 0 ] && _boxsession_unlock "$_lock"
        return 0
    fi
    _snapshot_session_end "$_id"
    [ "$_locked" -eq 0 ] && _boxsession_unlock "$_lock"
    # After the lock: the report walks the project, and an ended session is no one's to join.
    _snapshot_discard_unchanged "$_id"
    return 0
}

# _snapshot_session_end <session id>  ->  0. The session ends, keeping its snapshot for review and
# undo. A failure is left for agentvm_last_error: there is nobody to show it to at a window close.
# A session that could not be ended stays active with no row naming it, and the project's next
# snapshot is then refused as one Cadabra did not start, with the command that ends it.
_snapshot_session_end() {
    local _status
    agentvm_session_end "$1" >/dev/null
    _status=$?
    if [ "$_status" -ne 0 ]; then
        agentvm_last_error "$_status" >/dev/null
    fi
    return 0
}

# _snapshot_discard_unchanged <session id>  ->  0. The session is discarded when its project did
# not change, so there is nothing to review. A session ended or undone elsewhere counts the same.
_snapshot_discard_unchanged() {
    local _status
    local _summary
    _summary="$(agentvm_session_summary "$1")"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        agentvm_last_error "$_status" >/dev/null
        return 0
    fi
    local _changes="$(printf '%s\n' "$_summary" | /usr/bin/cut -f1)"
    if [ "$_changes" = "0" ]; then
        agentvm_session_discard "$1" >/dev/null
        _status=$?
        if [ "$_status" -ne 0 ]; then
            agentvm_last_error "$_status" >/dev/null
        fi
    fi
    return 0
}

# snapshot_release_own  ->  0. At quit: releases every row of this Cadabra process, so their
# sessions end now, not at the next launch.
snapshot_release_own() {
    local _me="$(_agentvm_owner_pid)"
    if [ -z "$_me" ]; then
        return 0
    fi
    local _window _id _project _pid
    snapshot_registry_rows | while IFS="$snapshot_tab" read -r _window _id _project _pid; do
        if [ "$_pid" = "$_me" ]; then
            snapshot_release "$_window"
        fi
    done
    return 0
}

# snapshot_release_stale  ->  0. At launch: releases the rows of Cadabra processes that are gone (a
# crash or force quit), so their sessions end and the projects can have new ones. A row with no
# pid ("-") is released too.
snapshot_release_stale() {
    local _window _id _project _pid
    snapshot_registry_rows | while IFS="$snapshot_tab" read -r _window _id _project _pid; do
        case "$_pid" in
            ''|*[!0123456789]*) ;;
            *) kill -0 "$_pid" 2>/dev/null
               if [ $? -eq 0 ]; then
                   continue
               fi ;;
        esac
        snapshot_release "$_window"
    done
    return 0
}

# _snapshot_changes_text <window>  ->  1 when the window has no snapshot; else 0, with _snap_text
# and _snap_help, the caller's locals, set to what the project changed ("3 changes, 1 flagged",
# "no changes yet") and the tooltip's lines on it.
_snapshot_changes_text() {
    local _row="$(snapshot_registry_row "$1")"
    if [ -z "$_row" ]; then
        return 1
    fi
    local _id="$(printf '%s\n' "$_row" | /usr/bin/cut -f2)"
    local _project="$(printf '%s\n' "$_row" | /usr/bin/cut -f3)"
    local _summary
    _summary="$(agentvm_session_summary "$_id")"
    local _status=$?
    if [ "$_status" -ne 0 ] || [ -z "$_summary" ]; then
        _snap_text="changes unavailable"
        _snap_help="What the project changed since its snapshot cannot be read: $(agentvm_last_error "$_status")"
        return 0
    fi
    local _changes _high _medium _warnings _flagged
    IFS="$snapshot_tab" read -r _changes _high _medium _warnings _flagged <<EOF
$_summary
EOF
    case "$_changes$_high$_medium$_warnings" in
        ''|*[!0123456789]*)
            _snap_text="changes unavailable"
            _snap_help="agent-vm's report on the project could not be read."
            return 0 ;;
    esac
    local _count=$((_high + _medium))
    case "$_changes" in
        0) _snap_text="no changes yet" ;;
        1) _snap_text="1 change" ;;
        *) _snap_text="$_changes changes" ;;
    esac
    if [ "$_count" -gt 0 ]; then
        _snap_text="$_snap_text, $_count flagged"
    fi
    _snap_help="Cadabra took a snapshot of $_project when the session started (AgentVM session $_id), so what the session changes there can be reviewed and undone."
    if [ "$_count" -gt 0 ]; then
        _snap_help="$_snap_help${snapshot_newline}Flagged, since they can run code later on this Mac: $_flagged"
    fi
    if [ "$_warnings" != "0" ]; then
        _snap_help="$_snap_help${snapshot_newline}agent-vm has warnings about this report: agent-vm session report $_id lists them."
    fi
    return 0
}

# snapshot_line_show <window>  ->  0. A window on this Mac with a snapshot gets the line, in the
# box line's place (slot 543 of aichat.chat.json, the same ids: a window has one or the other).
# A window whose box line is up instead has it restated, now with the changes.
snapshot_line_show() {
    local _box_line="$(pb_get "aichatv2_boxline_$1")"
    if [ -n "$_box_line" ]; then
        boxsession_line_refresh "$1"
        return 0
    fi
    local _stamp="$(pb_get "aichatv2_snapshot_$1")"
    if [ -z "$_stamp" ]; then
        return 0
    fi
    local _started="${_stamp#*"$snapshot_tab"}"
    local _head="Project snapshot"
    case "$_started" in
        ''|*[!0123456789]*) ;;
        *) _head="Project snapshot at $(/bin/date -r "$_started" +%H:%M)" ;;
    esac
    pb_set "aichatv2_snapline_$1" "$_head"
    "$dialog" "$1" "$boxsession_line_row_id" omc_remove_element 2>/dev/null
    "$dialog" "$1" "$boxsession_line_slot_id" omc_insert_element "{\"type\":\"HStack\",\"id\":$boxsession_line_row_id,\"properties\":{\"spacing\":8,\"padding\":{\"top\":0,\"leading\":14,\"bottom\":6,\"trailing\":14},\"frame\":{\"maxWidth\":\"infinity\",\"alignment\":\"leading\"}},\"children\":[{\"type\":\"Label\",\"id\":$boxsession_line_id,\"properties\":{\"title\":\"\",\"systemImage\":\"$snapshot_line_icon\",\"font\":\"footnote\",\"foregroundStyle\":\"secondary\",\"frame\":{\"maxWidth\":\"infinity\",\"alignment\":\"leading\"}}}]}"
    snapshot_line_refresh "$1"
}

# snapshot_line_refresh <window>  ->  0. Restates a window's own snapshot line (one on this Mac;
# the box line restates itself). Nothing for a window without one.
snapshot_line_refresh() {
    local _head="$(pb_get "aichatv2_snapline_$1")"
    if [ -z "$_head" ]; then
        return 0
    fi
    pb_set "aichatv2_snapline_at_$1" "$(/bin/date +%s)"
    local _snap_text _snap_help
    _snapshot_changes_text "$1" || return 0
    "$dialog" "$1" "$boxsession_line_id" "$_head - $_snap_text"
    "$dialog" "$1" "$boxsession_line_id" omc_set_property help "$_snap_help"
    return 0
}

# snapshot_line_focus <window>  ->  0. The window came to the front: its own snapshot line is
# refreshed unless that happened less than snapshot_line_focus_gap seconds ago.
snapshot_line_focus() {
    local _head="$(pb_get "aichatv2_snapline_$1")"
    if [ -z "$_head" ]; then
        return 0
    fi
    local _at="$(pb_get "aichatv2_snapline_at_$1")"
    local _now="$(/bin/date +%s)"
    case "$_at" in
        ''|*[!0123456789]*) ;;
        *)
            if [ $((_now - _at)) -lt "$snapshot_line_focus_gap" ]; then
                return 0
            fi ;;
    esac
    snapshot_line_refresh "$1"
}
