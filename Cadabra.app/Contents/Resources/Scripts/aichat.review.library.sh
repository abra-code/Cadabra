#!/bin/sh
# aichat.review.library.sh
#
# The Review Changes window (aichat.review.json): what a project snapshot's session changed (see
# aichat.snapshot.library.sh), flagged entries first; the selected entry against its copy in the
# snapshot; undo of one entry or of all; or keeping the changes and deleting the snapshot.
#
# OPENED FOR A SESSION. Whoever opens it puts the session id in REVIEW_REQUEST_KEY
# (review_request) and chains aichat.review: the Changes... button on a chat window's line
# (aichat.chat.review.sh), Review Changes on a history row (aichat.history.review.sh), and the
# question at a window's close when the session left high-risk changes (aichat.chat.cancel.sh).
# init moves the id into the window's own key, so review windows on different sessions can be
# open together.
#
# THE TABLE (910) shows three columns and carries seven hidden ones, read back by the selection
# handler: 1 a mark for a flagged change (a red circle for high, a yellow one for medium, empty
# otherwise: a narrow column to scan a long list by), 2 change ("Added folder (4 inside)"), 3 path;
# hidden: 4 why it is flagged (shown in the detail pane, where there is room for it), 5 type,
# 6 size, 7 previous size, 8 the folder whose change covers the entry, 9 a symbolic link's target,
# 10 the severity as agent-vm names it; "-" for none in 5-10. An entry covered by
# a folder's change (a flagged file inside a new folder) is listed for its flag, under that folder,
# and is undone with the folder, never on its own: agent-vm refuses that.
#
# THE DIFF (922) is ActionUI's Diff element, given two files: the entry's copy in the snapshot
# and the entry in the project, an empty file standing in for a side that does not exist. It shows
# a note instead of a diff for a file that is not UTF-8 text or is larger than 4 MB.
#
# UNDO puts entries back from the snapshot (agent-vm session undo). What the session left there is
# moved into the session's folder in agent-vm's store, never deleted. While a chat window still
# works on the project its agent may change the files again, so the summary and the confirmations
# say to stop it first; Undo All and Keep Changes wait until no window uses the session (see
# review_paint).
[ -n "${__AICHAT_REVIEW_LIB:-}" ] && return 0
__AICHAT_REVIEW_LIB=1

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.snapshot.library.sh"

REVIEW_REQUEST_KEY="cadabra_review_request"
# The header's four values (Project, Snapshot, Session, Changes) and the one-line note under
# them, a Label shown only when there is something to say (review_header).
review_project_id=901
review_snapshot_id=902
review_session_id=903
review_changes_id=904
review_note_id=905
review_table_id=910
review_head_id=920
review_lines_id=921
review_diff_id=922
# The scroll view holding the diff: the Diff element is as tall as its lines, so this is what is
# shown and hidden, and what keeps a long file from pushing the buttons off the window.
review_diff_scroll_id=923
review_undo_one_id=930
review_undo_all_id=931
review_keep_id=932

# review_context_key <window>  ->  the window's pasteboard key: the session id it shows.
review_context_key() {
    printf 'aichatv2_review_%s\n' "$1"
}

# review_session_file <window>  ->  the file holding the window's session row (agentvm_sessions),
# as the last paint read it, for the handlers after it.
review_session_file() {
    printf '%s\n' "${TMPDIR:-/tmp}/cadabra-review.$1.session"
}

# review_session_row <window>  ->  that row, or nothing.
review_session_row() {
    /bin/cat "$(review_session_file "$1")" 2>/dev/null
}

# review_window_session <window>  ->  the session id the window shows, or nothing.
review_window_session() {
    pb_get "$(review_context_key "$1")"
}

# review_request <session id>  ->  0 once the next review window will open on it; 2 for something
# that is not a session id. The caller chains aichat.review.
review_request() {
    agentvm_valid_session_id "$1" || return 2
    pb_set "$REVIEW_REQUEST_KEY" "$1"
}

# review_take_request <window>  ->  0. init: the requested session becomes the window's own.
review_take_request() {
    local _id="$(pb_get "$REVIEW_REQUEST_KEY")"
    pb_set "$REVIEW_REQUEST_KEY" ""
    pb_set "$(review_context_key "$1")" "$_id"
}

# review_forget <window>  ->  0. The window closes: its key and file go.
review_forget() {
    pb_set "$(review_context_key "$1")" ""
    /bin/rm -f "$(review_session_file "$1")"
}

# _review_empty_file  ->  an empty file, the side of a diff that does not exist.
_review_empty_file() {
    local _file="${TMPDIR:-/tmp}/cadabra-review-empty"
    printf '' 2>/dev/null > "$_file"
    printf '%s\n' "$_file"
}

# _review_state_text <state>  ->  the session's state, for the summary.
_review_state_text() {
    case "$1" in
        active)    printf '%s\n' "in use by a chat window" ;;
        ended)     printf '%s\n' "ended" ;;
        undone)    printf '%s\n' "undone" ;;
        discarded) printf '%s\n' "snapshot deleted" ;;
        *)         printf '%s\n' "$1" ;;
    esac
}

# _review_size <bytes>  ->  "14 bytes", "1 byte", or format_bytes's text from 1 KB up.
_review_size() {
    case "$1" in
        ''|-|*[!0123456789]*) printf '%s\n' "an unknown size" ;;
        1) printf '1 byte\n' ;;
        *) if [ "$1" -lt 1024 ]; then
               printf '%s bytes\n' "$1"
           else
               format_bytes "$1"
           fi ;;
    esac
}

# review_header <window> <project> <snapshot> <session> <changes> [note]  ->  0. The header's four
# values, "-" for one that is not known, and the note under them, hidden when there is none. The
# note is set as the Label's value: a Label shows its value, not a title set later.
review_header() {
    "$dialog" "$1" "$review_project_id" "${2:--}"
    "$dialog" "$1" "$review_snapshot_id" "${3:--}"
    "$dialog" "$1" "$review_session_id" "${4:--}"
    "$dialog" "$1" "$review_changes_id" "${5:--}"
    if [ -n "${6:-}" ]; then
        "$dialog" "$1" "$review_note_id" "$6"
        "$dialog" "$1" "$review_note_id" omc_show
    else
        "$dialog" "$1" "$review_note_id" omc_hide
    fi
    return 0
}

# review_paint <window>  ->  0. Reads the session and its changes again and shows them: the
# summary, the table with nothing selected, the detail pane cleared, and the buttons that apply. A
# session agent-vm no longer has, or whose snapshot is deleted, says why in the header's note.
review_paint() {
    local _window="$1"
    local _id="$(review_window_session "$_window")"
    local _row=""
    local _sessions=""
    local _listed=0
    agentvm_valid_session_id "$_id"
    if [ $? -eq 0 ]; then
        _sessions="$(agentvm_sessions)"
        _listed=$?
        _row="$(printf '%s\n' "$_sessions" | snapshot_session="$_id" /usr/bin/awk -F'\t' '$1 == ENVIRON["snapshot_session"] { print; exit }')"
    fi
    printf '%s\n' "$_row" > "$(review_session_file "$_window")"
    "$dialog" "$_window" "$review_table_id" omc_table_remove_all_rows
    # Setting rows keeps a selected row that is still there selected (by its first column, the
    # flag, which many rows share), and a click on a selected row fires nothing: the detail pane
    # cleared below could not be shown again, and Show in Finder would read the old row.
    "$dialog" "$_window" "$review_table_id" omc_deselect
    review_detail "$_window" ""
    local _button
    for _button in $review_undo_all_id $review_keep_id; do
        "$dialog" "$_window" "$_button" omc_disable
    done
    if [ "$_listed" -ne 0 ]; then
        review_header "$_window" "" "" "$_id" "" "AgentVM's sessions cannot be listed: $(agentvm_last_error "$_listed")"
        return 0
    fi
    if [ -z "$_row" ]; then
        review_header "$_window" "" "" "$_id" "" "AgentVM no longer has this session, so there is nothing to review or undo."
        return 0
    fi
    local _state="$(printf '%s\n' "$_row" | /usr/bin/cut -f2)"
    local _project="$(printf '%s\n' "$_row" | /usr/bin/cut -f3)"
    local _started="$(printf '%s\n' "$_row" | /usr/bin/cut -f4)"
    local _when=""
    case "$_started" in
        ''|*[!0123456789]*) ;;
        *) _when="$(/bin/date -r "$_started" '+%Y-%m-%d at %H:%M')" ;;
    esac
    local _session="$_id - $(_review_state_text "$_state")"
    if [ "$_state" = "discarded" ]; then
        review_header "$_window" "$_project" "$_when" "$_session" "" "The changes were kept and the snapshot deleted, so there is nothing left to review or undo."
        return 0
    fi
    local _rows
    _rows="$(agentvm_session_changes "$_id")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        review_header "$_window" "$_project" "$_when" "$_session" "" "What changed cannot be read: $(agentvm_last_error "$_status")"
        return 0
    fi
    # Changes undo restores (not covered by a folder's), and those flagged, the folder's own or
    # those inside it, as on the window's line.
    local _counts="$(printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' 'NF && $8 == "-" { n++; if ($1 != "-") f++ } END { print n + 0, f + 0 }')"
    local _count="${_counts% *}" _flagged="${_counts#* }"
    local _text
    case "$_count" in
        0) _text="None" ;;
        *) _text="$_count" ;;
    esac
    if [ "$_flagged" != "0" ]; then
        _text="$_text, $_flagged flagged: can run code later on this Mac"
    fi
    local _users="$(snapshot_session_users "$_id")"
    local _note=""
    if [ "$_users" != "0" ]; then
        _note="Stop the chat window's agent before undoing a change. Undo All and Keep Changes wait until that window is closed."
    fi
    review_header "$_window" "$_project" "$_when" "$_session" "$_text" "$_note"
    printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' 'BEGIN { OFS = "\t" } NF {
        flag = ($1 == "high") ? "\360\237\224\264" : ($1 == "medium") ? "\360\237\237\241" : ""
        change = $2
        if ($10 != "-" && $10 + 0 > 0) change = change " (" $10 " inside)"
        why = ($4 == "-") ? "" : $4
        if ($8 != "-") why = (why == "" ? "" : why "; ") "inside " $8 ", undone with it"
        print flag, change, $3, why, $5, $6, $7, $8, $9, $1
    }' | "$dialog" "$_window" "$review_table_id" omc_table_set_rows_from_stdin
    # Undo All and Keep wait until no chat window uses the session. Keeping deletes the snapshot it
    # needs. Undo All leaves it undone, which agent-vm can neither end nor undo again: the window's
    # agent would go on changing the project with no undo, while its line went on counting.
    if [ "$_users" = "0" ]; then
        case "$_state:$_count" in
            active:0|ended:0) ;;
            active:*|ended:*) "$dialog" "$_window" "$review_undo_all_id" omc_enable ;;
        esac
        "$dialog" "$_window" "$review_keep_id" omc_enable
    fi
    return 0
}

# review_detail <window> <selected row, tab-joined, or nothing>  ->  0. The detail pane: what the
# change is and why it is flagged, and for a file its diff against the snapshot. Undo This Change
# is enabled for an entry that can be undone on its own, in a session that can still be undone.
review_detail() {
    local _window="$1" _selected="$2"
    "$dialog" "$_window" "$review_undo_one_id" omc_disable
    if [ -z "$_selected" ]; then
        "$dialog" "$_window" "$review_head_id" "Select a change to see it."
        "$dialog" "$_window" "$review_lines_id" ""
        "$dialog" "$_window" "$review_diff_scroll_id" omc_hide
        return 0
    fi
    # cut, not a tab-separated read: the flag and why columns are empty for an unflagged change,
    # and read would merge an empty field with the next (tab is IFS whitespace).
    local _change="$(printf '%s\n' "$_selected" | /usr/bin/cut -f2)"
    local _path="$(printf '%s\n' "$_selected" | /usr/bin/cut -f3)"
    local _why="$(printf '%s\n' "$_selected" | /usr/bin/cut -f4)"
    local _type="$(printf '%s\n' "$_selected" | /usr/bin/cut -f5)"
    local _size="$(printf '%s\n' "$_selected" | /usr/bin/cut -f6)"
    local _previous="$(printf '%s\n' "$_selected" | /usr/bin/cut -f7)"
    local _covering="$(printf '%s\n' "$_selected" | /usr/bin/cut -f8)"
    local _target="$(printf '%s\n' "$_selected" | /usr/bin/cut -f9)"
    local _severity="$(printf '%s\n' "$_selected" | /usr/bin/cut -f10)"
    local _row="$(review_session_row "$_window")"
    local _state="$(printf '%s\n' "$_row" | /usr/bin/cut -f2)"
    local _project="$(printf '%s\n' "$_row" | /usr/bin/cut -f3)"
    local _snapshot="$(printf '%s\n' "$_row" | /usr/bin/cut -f5)"
    "$dialog" "$_window" "$review_head_id" "$_change: $_path"
    local _lines=""
    case "$_change" in
        Modified*) _lines="Was $(_review_size "$_previous"), now $(_review_size "$_size")." ;;
        Deleted*)  [ "$_type" = "directory" ] || _lines="Was $(_review_size "$_previous")." ;;
        Added*)    [ "$_type" = "directory" ] || _lines="$(_review_size "$_size")." ;;
    esac
    if [ "$_type" = "symlink" ] && [ "$_target" != "-" ]; then
        _lines="A symbolic link to $_target."
    fi
    # The table's Why, less the note on a covering folder, which is said in full below. Cut as that
    # exact suffix: a flag's own reason can say "inside" too ("git commands run inside it").
    local _flag_reason="$_why"
    if [ "$_covering" != "-" ]; then
        _flag_reason="${_flag_reason%"inside $_covering, undone with it"}"
        _flag_reason="${_flag_reason%"; "}"
    fi
    if [ -n "$_flag_reason" ]; then
        local _risk="Flagged"
        case "$_severity" in
            high)   _risk="High risk" ;;
            medium) _risk="Medium risk" ;;
        esac
        _lines="${_lines:+$_lines$snapshot_newline}$_risk: $_flag_reason"
    fi
    if [ "$_covering" != "-" ]; then
        _lines="${_lines:+$_lines$snapshot_newline}Inside the folder $_covering, which the session added or replaced: undoing that folder undoes this too, and it cannot be undone on its own."
    fi
    "$dialog" "$_window" "$review_lines_id" "$_lines"
    if [ "$_type" = "file" ] && [ -n "$_project" ] && [ -n "$_snapshot" ] && [ "$_snapshot" != "-" ]; then
        local _empty="$(_review_empty_file)"
        local _old="$_snapshot/$_path" _new="$_project/$_path"
        [ -f "$_old" ] || _old="$_empty"
        [ -f "$_new" ] || _new="$_empty"
        "$dialog" "$_window" "$review_diff_id" omc_set_property oldFile "$_old"
        "$dialog" "$_window" "$review_diff_id" omc_set_property newFile "$_new"
        "$dialog" "$_window" "$review_diff_scroll_id" omc_show
    else
        "$dialog" "$_window" "$review_diff_scroll_id" omc_hide
    fi
    case "$_state" in
        active|ended)
            if [ "$_covering" = "-" ]; then
                "$dialog" "$_window" "$review_undo_one_id" omc_enable
            fi ;;
    esac
    return 0
}

# _review_busy_note <session id>  ->  the confirmation's sentence for a session a chat window still
# uses, or nothing.
_review_busy_note() {
    local _users="$(snapshot_session_users "$1")"
    if [ "$_users" != "0" ]; then
        printf '%s\n' "

A chat window still works on this project. If its agent is working, stop it first, or it may change the files again."
    fi
}

# review_undo <window> [path]  ->  0. Asks, then puts back the one entry, or every change, as it
# was in the snapshot, says what could not be put back, and paints again.
review_undo() {
    local _window="$1" _path="${2:-}"
    local _id="$(review_window_session "$_window")"
    agentvm_valid_session_id "$_id" || return 0
    # Undo All is refused while a window uses the session (see review_paint); checked again here,
    # as the window may have started on the project since the paint.
    if [ -z "$_path" ]; then
        local _users="$(snapshot_session_users "$_id")"
        if [ "$_users" != "0" ]; then
            "$alert" --level caution --title "$APPLET_NAME" --ok "OK" \
                "A chat window still works on this project. Close it first: after Undo All its session could not be undone again, while its agent went on changing the project."
            review_paint "$_window"
            return 0
        fi
    fi
    local _title _text _ok
    if [ -n "$_path" ]; then
        _title="Undo the change to $_path?"
        _text="It is put back as it was in the snapshot."
        _ok="Undo Change"
    else
        _title="Undo every change in the project?"
        _text="Everything the session changed is put back as it was in the snapshot, and the session cannot be undone again afterwards."
        _ok="Undo All"
    fi
    _text="$_text What the session left there is kept in the session's folder in AgentVM's store, not deleted.$(_review_busy_note "$_id")"
    "$alert" --level caution --title "$_title" --ok "$_ok" --cancel "Cancel" "$_text"
    local _answer=$?
    if [ "$_answer" -ne 0 ]; then
        return 0
    fi
    local _result
    if [ -n "$_path" ]; then
        _result="$(agentvm_session_undo "$_id" "$_path")"
    else
        _result="$(agentvm_session_undo "$_id")"
    fi
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        "$alert" --level stop --title "Could not undo" --ok "OK" "$(agentvm_last_error "$_status")"
        review_paint "$_window"
        return 0
    fi
    local _restored _remaining _failed _failures _state
    IFS="$snapshot_tab" read -r _restored _remaining _failed _failures _state <<REVIEW_UNDO
$_result
REVIEW_UNDO
    if [ "$_failed" != "0" ]; then
        "$alert" --level caution --title "Some changes were not undone" --ok "OK" \
            "$_restored put back; these could not be: $_failures"
    fi
    review_paint "$_window"
    return 0
}

# review_keep <window>  ->  0 once the snapshot is deleted (the window then closes), 1 when the user
# canceled or it could not be deleted. Asks first.
review_keep() {
    local _window="$1"
    local _id="$(review_window_session "$_window")"
    agentvm_valid_session_id "$_id" || return 1
    local _users="$(snapshot_session_users "$_id")"
    if [ "$_users" != "0" ]; then
        "$alert" --level caution --title "$APPLET_NAME" --ok "OK" \
            "A chat window still works on this project. Close it first: its session needs the snapshot."
        return 1
    fi
    "$alert" --level caution --title "Keep the changes and delete the snapshot?" --ok "Keep Changes" --cancel "Cancel" \
        "The project stays as it is now, and the session's changes can no longer be undone. What earlier undos moved aside is deleted with the snapshot."
    local _answer=$?
    if [ "$_answer" -ne 0 ]; then
        return 1
    fi
    agentvm_session_discard "$_id" >/dev/null
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        "$alert" --level stop --title "Could not delete the snapshot" --ok "OK" "$(agentvm_last_error "$_status")"
        return 1
    fi
    return 0
}

# review_reveal <window> <selected path, or nothing>  ->  0. Shows the entry in Finder, or the
# project folder when nothing is selected or the entry is gone from the project. CADABRA_OPEN is
# the test seam for /usr/bin/open.
review_reveal() {
    local _project="$(review_session_row "$1" | /usr/bin/cut -f3)"
    if [ -z "$_project" ] || [ ! -d "$_project" ]; then
        return 0
    fi
    local _target="$_project"
    if [ -n "${2:-}" ] && { [ -e "$_project/$2" ] || [ -L "$_project/$2" ]; }; then
        _target="$_project/$2"
    fi
    "${CADABRA_OPEN:-/usr/bin/open}" -R "$_target" >/dev/null 2>&1
    return 0
}

# review_pick_session <meta.json>  ->  the session to review for a saved conversation: the newest
# of its snapshots whose session agent-vm still has and has not discarded, else the newest of
# them; nothing when it has none.
review_pick_session() {
    local _ids
    _ids="$(/usr/bin/jq -r '(.snapshots // [])[] | .session // empty' "$1" 2>/dev/null)"
    if [ -z "$_ids" ]; then
        return 0
    fi
    local _live="$(agentvm_sessions 2>/dev/null | /usr/bin/awk -F'\t' '$2 != "discarded" { print $1 }')"
    /bin/rm -f "$agentvm_err_file"
    local _pick="$(printf '%s\n' "$_ids" | review_live="$_live" /usr/bin/awk '
        BEGIN { n = split(ENVIRON["review_live"], ids, "\n"); for (i = 1; i <= n; i++) ok[ids[i]] = 1 }
        { all[NR] = $0 }
        END {
            for (i = NR; i >= 1; i--) if (all[i] in ok) { print all[i]; exit }
            print all[NR]
        }')"
    printf '%s\n' "$_pick"
}

# review_offer_at_close  ->  0. After a window's snapshot_release: when the session it ended left
# changes flagged high (able to run code later on this Mac), asks whether to review them now and,
# when the user says so, chains the review window (omc_next_command opens it after the handler ends).
review_offer_at_close() {
    case "$snapshot_released_high" in
        ''|0|*[!0123456789]*) return 0 ;;
    esac
    local _what="$snapshot_released_high changes that can"
    if [ "$snapshot_released_high" = "1" ]; then
        _what="1 change that can"
    fi
    "$alert" --level caution --title "Review the changes in the project?" --ok "Review Changes" --cancel "Later" \
        "The session in the closed window made $_what run code later on this Mac (a git hook, a script or a link out of the project, say). Its snapshot is kept, so they can be reviewed and undone now, or later from the conversation's row in the history."
    local _answer=$?
    if [ "$_answer" -ne 0 ]; then
        return 0
    fi
    review_request "$snapshot_released_session"
    local _status=$?
    if [ "$_status" -eq 0 ]; then
        "$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.review"
    fi
    return 0
}
