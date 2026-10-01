#!/bin/sh
# Tests/48-project-snapshot.test.sh - a chat window's project snapshot (aichat.snapshot.library.sh):
# agent-vm's session JSON as the library reads it, the settings, chat init's snapshot before the
# transport, windows sharing a project's session, the changes on the window's line, and the end of
# a session when its last window goes.
#
# agent-vm is fake_agent_vm.sh, which hands `session` commands to the real agent-vm in a store
# inside this test's folder: sessions need no virtual machine, and their snapshots are what is
# checked. Without a real agent-vm (~/.local/bin/agent-vm of the account running the suite, or
# CADABRA_TEST_SESSION_AGENT_VM), only the sections that need none run.
#
# Needs the sandbox off (agent-vm's store and its clones). POSIX sh only. Validate with "sh -n",
# never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.snapshot.library.sh
FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
export FAKE_AGENTVM_DIR
REGISTRY="$HOME/Library/Application Support/Cadabra/snapshot-sessions.tsv"
BOX_REGISTRY="$HOME/Library/Application Support/Cadabra/box-sessions.tsv"
PROJECT="$OMCTEST_WORK/src/app"
OTHER="$OMCTEST_WORK/src/other"
PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
CONVERT="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_json.py"
TAB=$(printf '\t')

unset CADABRA_AGENT_VM AGENT_VM_HOME
CADABRA_AGENT_VM="$OMCTEST_WORK/no-agent-vm-in-tests"
CADABRA_BOXWATCH_EVERY=1
CADABRA_BOXWATCH_FOR=1
export CADABRA_BOXWATCH_EVERY CADABRA_BOXWATCH_FOR

# The real agent-vm, in the home folder of the account running the suite ($HOME is the test's).
REAL_AGENT_VM="${CADABRA_TEST_SESSION_AGENT_VM:-}"
if [ -z "$REAL_AGENT_VM" ]; then
    user_home="$(eval "printf '%s' ~$(/usr/bin/id -un)")"
    REAL_AGENT_VM="$user_home/.local/bin/agent-vm"
fi

with_fake() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib "$LIB" "$@" )
}
message() { cad_call_lib "$LIB" agentvm_last_error "$1"; }
col() { /usr/bin/cut -f"$1"; }
logged() { /usr/bin/grep "^$1" "$FAKE_AGENTVM_DIR/log" 2>/dev/null; }
# real <args...>  ->  the real agent-vm on the fake's session store.
real() { AGENT_VM_HOME="$FAKE_AGENTVM_DIR/session-store" "$REAL_AGENT_VM" "$@"; }
# state <session id>  ->  the session's state, from the real agent-vm.
state() { real session list --json | /usr/bin/jq -r --arg id "$1" '.[] | select(.id == $id) | .state'; }
# line_text <window>  ->  the text last written to the window's line (not its tooltip).
line_text() {
    /usr/bin/awk -F'\t' -v w="$1" '$1 == w && $2 == "544" && $3 !~ /^omc_/ { sub(/ $/, "", $3); last = $3 } END { print last }' "$OMCTEST_UI/journal.tsv"
}

engine() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM
      . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.chat.engine.library.sh" >/dev/null 2>&1
      prefs="$OMCTEST_WORK/no-such-registry.plist"
      "$@" >/dev/null 2>&1
      printf '%s\n' "$?" )
}

# fake_reset - a fake whose sessions go to the real agent-vm, a fresh project, no registries.
fake_reset() {
    if [ -d "$FAKE_AGENTVM_DIR/session-store" ]; then
        real session list --json 2>/dev/null | /usr/bin/jq -r '.[] | select(.state != "discarded") | .id' | \
            while read -r id; do real session discard "$id" >/dev/null 2>&1; done
    fi
    /bin/rm -rf "$FAKE_AGENTVM_DIR" "$PROJECT" "$OTHER"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR" "$PROJECT/src" "$PROJECT/.git/hooks" "$OTHER"
    /bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-b1.json"
    /usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
    printf '%s\n' "$REAL_AGENT_VM" > "$FAKE_AGENTVM_DIR/session-agent-vm"
    printf 'hello\n' > "$PROJECT/src/main.c"
    printf 'other\n' > "$OTHER/notes.txt"
    /bin/rm -f "$REGISTRY" "$BOX_REGISTRY"
}

# prefs_reset <mac setting> - the MCP settings at their defaults with the project set, and the
# snapshot on this Mac as given.
prefs_reset() {
    cad_reset
    cad_call mcp_prefs_write_defaults >/dev/null 2>&1
    cad_call mcp_prefs_set_string servers/local/project "$PROJECT"
    cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_set_setting mac "$1"
}

section "agent-vm's session JSON, as the library reads it"
row=$("$PY" "$CONVERT" sessions < "$FIXTURES/session-start.json")
check "session start: id, state, project, start, snapshot" \
    "20260930-215049-4171|active|/Users/you/Development/snapcap/app|1790830249|/Users/you/Development/snapcap/store/Sessions/20260930-215049-4171/snapshot" \
    "$(printf '%s\n' "$row" | /usr/bin/tr '\t' '|')"
check "session list: a row each"          "1" "$("$PY" "$CONVERT" sessions < "$FIXTURES/session-list.json" | /usr/bin/awk 'END { print NR }')"
summary=$("$PY" "$CONVERT" report-summary < "$FIXTURES/session-report.json")
check "report: 6 changes, 3 high, 1 medium, no warnings" "6|3|1|0" "$(printf '%s\n' "$summary" | /usr/bin/cut -f1-4 | /usr/bin/tr '\t' '|')"
check "  a new folder holding a git hook counts once, as high" "1" \
    "$(/usr/bin/jq '[.changes[] | select(.coveredByAncestor == true)] | length > 0' "$FIXTURES/session-report.json" | /usr/bin/sed 's/true/1/')"
check "  agent-vm's own summary counts the entries" "5" "$(/usr/bin/jq '.summary.flaggedHigh' "$FIXTURES/session-report.json")"
check "  the flagged list names the hook first, with its reason" "1" \
    "$(cad_has "$(printf '%s\n' "$summary" | /usr/bin/cut -f5)" '.git/hooks/pre-commit (git hook: runs automatically')"
check "  and the package manifest after the high ones" "1" \
    "$(printf '%s\n' "$summary" | /usr/bin/cut -f5 | /usr/bin/awk -F'; ' '{ print ($NF ~ /^package.json/) ? 1 : 0 }')"
check "no empty field"                    "0" "$(printf '%s\n%s\n' "$row" "$summary" | /usr/bin/awk -F'\t' '{ for (i = 1; i <= NF; i++) if ($i == "") n++ } END { print n + 0 }')"
check "JSON that is not a report fails"   "1" "$(printf '[]\n' | "$PY" "$CONVERT" report-summary >/dev/null 2>&1; echo $?)"

section "the settings"
cad_reset
check "off on this Mac, on in a box"      "false|true" \
    "$(cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_setting mac)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_setting box)"
cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_set_setting mac true
check "stored and read back"              "true" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_setting mac)"
"$cad_plister" set string "x" "$cad_settings" /servers/snapshot >/dev/null 2>&1
check "  something else reads as the default" "false" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_setting mac)"
check "  and storing again repairs it"    "0|true" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_set_setting mac true; echo $?)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_setting mac)"
check "another place is refused"          "2" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_set_setting cloud true; echo $?)"
check "a run-in names its place"          "mac|box|box" \
    "$(for r in mac box:b1 new:dev; do cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_place "$r"; done | /usr/bin/paste -sd'|' -)"

section "session ids are checked before agent-vm sees them"
check "a real one"                        "0" "$(cad_call_lib "$LIB" agentvm_valid_session_id 20260930-215049-4171; echo $?)"
check "one that would read as an option"  "1" "$(cad_call_lib "$LIB" agentvm_valid_session_id --all; echo $?)"
check "  or that is not hex"              "1" "$(cad_call_lib "$LIB" agentvm_valid_session_id 2026x; echo $?)"
fake_reset
check "  refused without running agent-vm" "2|" "$(with_fake agentvm_session_end ../x >/dev/null 2>&1; echo $?)|$(logged 'session')"

"$REAL_AGENT_VM" --version >/dev/null 2>&1
real_status=$?
if [ "$real_status" -ne 0 ]; then
    section "sessions with the real agent-vm: skipped, none at $REAL_AGENT_VM"
    check "(a real agent-vm is needed for the rest of this file)" "skipped" "skipped"
    omctest_end
    exit 0
fi

section "chat init takes no snapshot it was not asked for"
fake_reset
prefs_reset false
cad_pb_set aichatv2_open_w1 1
alerts_reset
check "this Mac's setting off: nothing"   "0|" "$(engine chat_engine_snapshot w1 true true)|$(logged 'session')"
prefs_reset true
check "a local model without tools: nothing" "0|" "$(engine chat_engine_snapshot w1 false false)|$(logged 'session')"
cad_call mcp_prefs_set_string servers/local/project ""
check "no project folder: nothing"        "0|" "$(engine chat_engine_snapshot w1 true true)|$(logged 'session')"
check "  and no alert"                    "0" "$(alerts_count)"

section "chat init takes the snapshot, and the window's line says so"
fake_reset
prefs_reset true
cad_pb_set aichatv2_open_w1 1
cad_journal_reset
alerts_reset
check "an agent on this Mac: taken"       "0" "$(engine chat_engine_snapshot w1 true true)"
id1=$(col 2 < "$REGISTRY")
check "  the registry names the window, the session and the project" "w1|$PROJECT|0" \
    "$(col 1 < "$REGISTRY")|$(col 3 < "$REGISTRY")|$(cad_call_lib "$LIB" agentvm_valid_session_id "$id1"; echo $?)"
check "  with this Cadabra's pid"         "1" "$(col 4 < "$REGISTRY" | /usr/bin/awk '/^[0-9]+$/ { print 1; exit }')"
check "  the session is active"           "active" "$(state "$id1")"
check "  the window's stamp names it"     "$id1" "$(cad_pb_get aichatv2_snapshot_w1 | col 1)"
check "  the line shows, with no changes yet" "1" "$(cad_has "$(line_text w1)" ' - no changes yet')"
check "  and when the snapshot was taken" "1" "$(cad_has "$(line_text w1)" 'Project snapshot at ')"
check "  no alert"                        "0" "$(alerts_count)"

section "a second window on the project shares its session"
cad_pb_set aichatv2_open_w2 1
check "taken"                             "0" "$(engine chat_engine_snapshot w2 false true)"
check "  the same session"                "$id1|2" "$(cad_call_lib "$LIB" snapshot_registry_row w2 | col 2)|$(cad_call_lib "$LIB" snapshot_session_users "$id1")"
check "  agent-vm keeps one"              "1" "$(real session list --json | /usr/bin/jq '[.[] | select(.state == "active")] | length')"

section "what the session changes shows on the line"
printf 'changed\n' >> "$PROJECT/src/main.c"
printf '#!/bin/sh\n' > "$PROJECT/.git/hooks/pre-commit"
/bin/chmod +x "$PROJECT/.git/hooks/pre-commit"
cad_journal_reset
with_fake snapshot_line_refresh w1
check "two changes, one flagged"          "1" "$(cad_has "$(line_text w1)" ' - 2 changes, 1 flagged')"
help=$(cad_journal 544 | /usr/bin/grep 'help' | /usr/bin/tail -1)
check "  the tooltip names the hook"      "1" "$(cad_has "$help" '.git/hooks/pre-commit (git hook')"
check "  and the session"                 "1" "$(cad_has "$help" "AgentVM session $id1")"
cad_journal_reset
with_fake snapshot_line_focus w1
check "coming to the front just after does not read it again" "0" "$(cad_writes 544)"

section "the conversation's record names the snapshot"
cad_pb_set aichatv2_session_w1 "20260930T000000Z-1"
hdir="$HOME/Library/Application Support/Cadabra/History/20260930T000000Z-1"
/bin/mkdir -p "$hdir"
printf '{"id": "20260930T000000Z-1"}\n' > "$hdir/meta.json"
with_fake snapshot_record_meta w1
with_fake snapshot_record_meta w1
check "once"                              "$id1|$PROJECT|1" \
    "$(/usr/bin/jq -r '[.snapshots[0].session, .snapshots[0].project, (.snapshots | length)] | join("|")' "$hdir/meta.json")"
cad_pb_set aichatv2_session_w1 ""

section "the session ends with its last window"
with_fake snapshot_release w1
check "one window left: still active"     "active|1" "$(state "$id1")|$(cad_call_lib "$LIB" snapshot_session_users "$id1")"
check "  the window's stamp is gone"      "" "$(cad_pb_get aichatv2_snapshot_w1)"
with_fake snapshot_release w2
check "the last one: ended, its snapshot kept for undo" "ended" "$(state "$id1")"
check "  the registry is empty"           "" "$(/bin/cat "$REGISTRY")"
check "  and the start lock, taken for the end, is free again" "0" \
    "$([ -d "$HOME/Library/Application Support/Cadabra/snapshot-start.lock" ] && echo 1 || echo 0)"
check "  and the project can have a new session" "0" "$(engine chat_engine_snapshot w1 true true)"
id2=$(col 2 < "$REGISTRY")
with_fake snapshot_release w1
check "a session that changed nothing is discarded" "discarded" "$(state "$id2")"

section "a session Cadabra did not start is not joined"
fake_reset
prefs_reset true
cad_pb_set aichatv2_open_w1 1
foreign=$(real session start --project "$PROJECT" --json | /usr/bin/jq -r .id)
alerts_reset
alert_answers_reset
alert_answer 1
check "Cancel stops the start"            "1|0" "$(engine chat_engine_snapshot w1 true true)|$([ -s "$REGISTRY" ] && echo 1 || echo 0)"
check "  the alert says whose it is and how to end it" "1|1" \
    "$(alerts_mention 'Cadabra did not start')|$(alerts_mention "agent-vm session end $foreign")"
check "  and leaves it alone"             "active" "$(state "$foreign")"
alert_answer 0
check "Start Without Snapshot starts without one" "0|0" "$(engine chat_engine_snapshot w1 true true)|$([ -s "$REGISTRY" ] && echo 1 || echo 0)"
real session discard "$foreign" >/dev/null 2>&1

section "a snapshot agent-vm refuses, or no agent-vm at all"
fake_reset
prefs_reset true
cad_pb_set aichatv2_open_w1 1
printf 'the project is on another volume\n' > "$FAKE_AGENTVM_DIR/fail-session-start"
alerts_reset
alert_answers_reset
alert_answer 1
check "agent-vm's reason is shown, and Cancel stops" "1|1" "$(engine chat_engine_snapshot w1 true true)|$(alerts_mention 'the project is on another volume')"
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-session-start"
alerts_reset
alert_answer 1
out=$( ( CADABRA_AGENT_VM="$OMCTEST_WORK/no-agent-vm-in-tests"; export CADABRA_AGENT_VM
         . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.chat.engine.library.sh" >/dev/null 2>&1
         chat_engine_snapshot w1 true true >/dev/null 2>&1; printf '%s\n' "$?" ) )
check "no agent-vm: the user is told it needs AgentVM" "1|1" "$out|$(alerts_mention 'A snapshot needs AgentVM')"
alert_answers_reset

section "a window in a box: the box's setting, never for a read-only share"
fake_reset
prefs_reset false
cad_pb_set aichatv2_open_w1 1
with_fake boxsession_registry_add w1 b1 no "$PROJECT" yes
check "read-only: none, even with the box's setting on" "0|" "$(engine chat_engine_snapshot w1 true true)|$(logged 'session start')"
with_fake boxsession_registry_add w1 b1 no "$PROJECT" no
cad_pb_set aichatv2_boxline_w1 "b1${TAB}2026-09-30T00:00:00Z${TAB}Kept AgentVM box b1 (stays running)"
cad_journal_reset
check "read-write: taken, though this Mac's setting is off" "0|1" "$(engine chat_engine_snapshot w1 true true)|$([ -s "$REGISTRY" ] && echo 1 || echo 0)"
check "  the box line says it, after the network" "1" "$(cad_has "$(line_text w1)" 'Kept AgentVM box b1 (stays running) - ')"
check "  with the changes"                "1" "$(cad_has "$(line_text w1)" ' - no changes yet')"
check "  and no line of its own"          "" "$(cad_pb_get aichatv2_snapline_w1)"
with_fake snapshot_release w1
with_fake boxsession_release w1

section "the rows of a Cadabra that is gone are released at launch"
fake_reset
prefs_reset true
cad_pb_set aichatv2_open_w1 1
engine chat_engine_snapshot w1 true true >/dev/null
id3=$(col 2 < "$REGISTRY")
printf 'changed\n' >> "$PROJECT/src/main.c"
/usr/bin/awk -F'\t' 'BEGIN { OFS = "\t" } { $4 = 999999; print }' "$REGISTRY" > "$REGISTRY.new" && /bin/mv "$REGISTRY.new" "$REGISTRY"
with_fake snapshot_release_stale
check "its session ends, with its changes kept" "ended|" "$(state "$id3")|$(/bin/cat "$REGISTRY")"
engine chat_engine_snapshot w1 true true >/dev/null
check "this Cadabra's own rows are released at quit" "0" \
    "$(with_fake snapshot_release_own; /usr/bin/awk 'END { print NR }' "$REGISTRY")"
engine chat_engine_snapshot w1 true true >/dev/null
id4=$(col 2 < "$REGISTRY")
/usr/bin/awk -F'\t' 'BEGIN { OFS = "\t" } { $4 = 999999; print }' "$REGISTRY" > "$REGISTRY.new" && /bin/mv "$REGISTRY.new" "$REGISTRY"
cad_pb_set aichatv2_open_w2 1
engine chat_engine_snapshot w2 true true >/dev/null
check "a window starting before the launch released them does not join the gone one's session" "1|0" \
    "$([ "$(col 2 < "$REGISTRY")" != "$id4" ] && echo 1)|$(/usr/bin/grep -c "^w1$TAB" "$REGISTRY")"
check "  whose session was released first (unchanged, so discarded)" "discarded" "$(state "$id4")"
with_fake snapshot_release w2

fake_reset
/bin/rm -rf "$FAKE_AGENTVM_DIR"
omctest_end
