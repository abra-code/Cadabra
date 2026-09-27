#!/bin/sh
# Tests/48-box-sessions.test.sh - a chat window's external agent in an agent-vm box
# (aichat.boxsession.library.sh): making or reusing the box, starting it, the warm-up exec that
# shares the project, the transport that runs the agent there, and the registry that releases
# the box when its window goes. agent-vm is fake_agent_vm.sh, as in tests 45-47.
#
# Needs the sandbox off (the release's stop job runs detached through agentvm_job.py, which
# uses ps). POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.boxsession.library.sh
FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
export FAKE_AGENTVM_DIR
REGISTRY="$HOME/Library/Application Support/Cadabra/box-sessions.tsv"
PROJECT="$OMCTEST_WORK/src/app"
TAB=$(printf '\t')
/bin/mkdir -p "$PROJECT"

unset CADABRA_AGENT_VM AGENT_VM_HOME

with_fake() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib "$LIB" "$@" )
}
message() { cad_call_lib "$LIB" agentvm_last_error "$1"; }
col() { /usr/bin/cut -f"$1"; }
logged() { /usr/bin/grep "^$1" "$FAKE_AGENTVM_DIR/log"; }

# fake_reset - a fake with a stopped box b1, a free VM slot, no registry.
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
    /bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-b1.json"
    /usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
    printf '0\n' > "$FAKE_AGENTVM_DIR/delay"
    /bin/rm -f "$REGISTRY"
}

# set_developer <key> <value> - /developer/<key> in the isolated settings file.
set_developer() {
    [ -f "$cad_settings" ] || {
        /bin/mkdir -p "$(/usr/bin/dirname "$cad_settings")"
        "$cad_plister" set dict "$cad_settings" / >/dev/null 2>&1
    }
    "$cad_plister" get type "$cad_settings" /developer >/dev/null 2>&1 || \
        "$cad_plister" insert developer dict "$cad_settings" / >/dev/null 2>&1
    "$cad_plister" get type "$cad_settings" "/developer/$1" >/dev/null 2>&1 || \
        "$cad_plister" insert "$1" string "" "$cad_settings" /developer >/dev/null 2>&1
    "$cad_plister" set string "$2" "$cad_settings" "/developer/$1" >/dev/null 2>&1
}

# field <json> <python expression over t> - one value of a transport, printed by Python.
field() {
    printf '%s' "$1" | "$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -c 'import json, sys; t = json.load(sys.stdin)["transport"]; print('"$2"')' 2>&1
}

# wait_for_log <prefix>  ->  the first log line starting with prefix, waiting up to 5 s for it.
wait_for_log() {
    w_left=50
    while :; do
        w_line=$(logged "$1" | /usr/bin/head -1)
        [ -n "$w_line" ] && break
        [ "$w_left" -le 0 ] && break
        w_left=$((w_left - 1))
        /bin/sleep 0.1
    done
    printf '%s\n' "$w_line"
}

if [ -n "${OMC_APP_PROCESS_ID:-}" ]; then
    owner_args=" --owner-pid $OMC_APP_PROCESS_ID"
    owner_pid="$OMC_APP_PROCESS_ID"
else
    owner_args=""
    owner_pid="-"
fi

# -----------------------------------------------------------------------------------------
section "a disposable box: made from the image with the agent's rules, started, shared"
fake_reset
box=$(with_fake boxsession_start w1 new:dev claude-code-acp "$PROJECT" no)
status=$?
check "it starts"                        "0" "$status"
case "$box" in
    cadabra-claude-code-acp-[0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef]) named=yes ;;
    *) named="no: $box" ;;
esac
check "  named cadabra-<agent>-<6 hex digits>" "yes" "$named"
check "  made disposable, allowlisted, with the catalog's rules" \
    "box create $box --image dev --net allowlist --allow pack:anthropic --disposable --json" "$(logged 'box create')"
check "  started with Cadabra as its owner" "box start $box$owner_args --json" "$(logged 'box start')"
check "  the project shared by a warm-up program" \
    "exec --box $box --project $PROJECT -- /usr/bin/true" "$(logged 'exec')"
check "  registered for its window" \
    "w1${TAB}$box${TAB}yes${TAB}$PROJECT${TAB}no${TAB}$owner_pid" "$(/bin/cat "$REGISTRY")"
other=$(with_fake boxsession_start w2 new:dev claude-code-acp "$PROJECT" no)
check "a second window gets a box of its own" "1" "$([ "$other" != "$box" ] && echo 1 || echo 0)"
check "  and a second row"                    "2" "$(/usr/bin/wc -l < "$REGISTRY" | /usr/bin/tr -d ' ')"

section "an agent the catalog does not know gets a box that reaches no host"
fake_reset
box=$(with_fake boxsession_start w1 new:dev "custom:3" "$PROJECT" no)
case "$box" in cadabra-custom-3-??????) named=yes ;; *) named="no: $box" ;; esac
check "its id made into a name agent-vm accepts" "yes" "$named"
check "  with no rules"                  "box create $box --image dev --net allowlist --disposable --json" "$(logged 'box create')"

section "a kept box: reused as it is, read-only when asked"
fake_reset
box=$(with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" yes)
check "it starts, under its own name"    "b1" "$box"
check "  nothing is made"                "" "$(logged 'box create')"
check "  the share is read-only"         "exec --box b1 --project $PROJECT --read-only -- /usr/bin/true" "$(logged 'exec')"
check "  registered as kept"             "w1${TAB}b1${TAB}no${TAB}$PROJECT${TAB}yes" "$(/usr/bin/cut -f1-5 "$REGISTRY")"
fake_reset
/bin/cp "$FIXTURES/box-status-ready.json" "$FAKE_AGENTVM_DIR/box-b1.json"
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
box=$(with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" no)
check "a box that runs is not started again" "b1|" "$box|$(logged 'box start')"
check "  and the full VM slots do not refuse it: it is one of them" "0" "$(cad_has "$(/bin/cat "$FAKE_AGENTVM_DIR/log")" 'doctor')"

fake_reset
/usr/bin/sed 's/"stopped"/"starting"/' "$FIXTURES/box-status-stopped.json" > "$FAKE_AGENTVM_DIR/box-b1.json"
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
box=$(with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" no)
check "a box that is starting is waited for" "b1|box start b1$owner_args --json" "$box|$(logged 'box start')"
check "  without the slot check"         "0" "$(cad_has "$(/bin/cat "$FAKE_AGENTVM_DIR/log")" 'doctor')"

section "a window that starts again gives up its earlier box"
fake_reset
first=$(with_fake boxsession_start w1 new:dev claude-code-acp "$PROJECT" no)
second=$(with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" no)
check "the earlier disposable box is gone" "0" "$([ -f "$FAKE_AGENTVM_DIR/box-$first.json" ] && echo 1 || echo 0)"
check "  and the window has one row, the new box" "w1${TAB}b1" "$(/usr/bin/cut -f1,2 "$REGISTRY")"

section "refusals leave agent-vm's reason, and a row to release"
fake_reset
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
box=$(with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" no)
status=$?
check "no free VM slot refuses the start" "1" "$status"
check "  saying why"                     "1" "$(cad_has "$(message "$status")" 'No virtual machine slot is free')"
check "  with nothing printed"           "" "$box"
check "  and the row written, for the release" "w1${TAB}b1" "$(/usr/bin/cut -f1,2 "$REGISTRY")"
fake_reset
printf 'the project cannot be your home folder or a folder that contains it' > "$FAKE_AGENTVM_DIR/exec-error"
box=$(with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" no)
status=$?
check "a share agent-vm refuses fails the start" "1" "$status"
check "  with agent-vm's own words"      "the project cannot be your home folder or a folder that contains it" "$(message "$status")"
fake_reset
with_fake boxsession_start w1 elsewhere claude-code-acp "$PROJECT" no >/dev/null
status=$?
check "an unknown choice is refused"     "2" "$status"
check "  naming the two forms"           "1" "$(cad_has "$(message "$status")" 'box:<name> or new:<image>')"
with_fake boxsession_start w1 box:b1 claude-code-acp relative/dir no >/dev/null
status=$?
check "a relative project is refused"    "2" "$status"
check "  before agent-vm runs"           "0" "$([ -f "$FAKE_AGENTVM_DIR/log" ] && echo 1 || echo 0)"
with_fake boxsession_start w1 box:-rm claude-code-acp "$PROJECT" no >/dev/null
check "a box name that reads as an option is refused" "2" "$?"
with_fake boxsession_start w1 "new:" claude-code-acp "$PROJECT" no >/dev/null
check "an empty image is refused"        "2" "$?"
check "  and nothing was registered"     "0" "$([ -f "$REGISTRY" ] && echo 1 || echo 0)"
with_fake boxsession_registry_add w1 b1 no "$OMCTEST_WORK/a${TAB}b" no
check "a project with a tab cannot break the registry" "2" "$?"
with_fake boxsession_start w1 new:dev claude-code-acp "$PROJECT" maybe >/dev/null
check "a read-only that is not yes or no is refused" "2" "$?"
check "  before a box is made"           "0" "$([ -f "$FAKE_AGENTVM_DIR/log" ] && echo 1 || echo 0)"
with_fake boxsession_registry_add w1 b1 "" "$PROJECT" no
check "an empty disposable column is refused" "2" "$?"
with_fake boxsession_registry_add w1 b1 no '/a\nb\tc' no
check "a project spelling \\n and \\t is kept as typed" '/a\nb\tc' "$(col 4 < "$REGISTRY")"
check "  on one line"                    "1" "$(/usr/bin/wc -l < "$REGISTRY" | /usr/bin/tr -d ' ')"
check "  and found by its window"        '/a\nb\tc' "$(with_fake boxsession_registry_row w1 | col 4)"

section "the transport runs the agent in the box, with one secret"
fake_reset
/bin/cp "$FIXTURES/secret-list.json" "$FAKE_AGENTVM_DIR/secret-list.json"
json=$(with_fake boxsession_transport "claude-agent-acp" w1 claude-code-acp b1 "$PROJECT" no free)
check "the command is agent-vm exec in the box" "['$FAKE', 'exec', '--box', 'b1', '--project', '$PROJECT']" "$(field "$json" 't["command"][:6]')"
check "  with the token agent-vm keeps"  "1" "$(cad_has "$json" '"--secret", "CLAUDE_CODE_OAUTH_TOKEN"')"
check "  and not the key it does not"    "0" "$(cad_has "$json" 'ANTHROPIC_API_KEY')"
check "  starting in the free mode"      "{'mode': 'bypassPermissions'}" "$(field "$json" 't["sessionConfig"]')"
check "  with no store setting"          "False" "$(field "$json" '"env" in t')"
json=$(with_fake boxsession_transport "codex-acp" w1 codex-acp b1 "$PROJECT" yes ask)
check "Codex gets the first secret agent-vm keeps" "1" "$(cad_has "$json" '"--secret", "OPENAI_API_KEY"')"
check "  and the read-only share"        "1" "$(cad_has "$json" '"--read-only"')"
json=$(with_fake boxsession_transport "my-claude --verbose" w1 "" b1 "$PROJECT" no free)
check "an edited command runs as typed"  "['--', 'my-claude', '--verbose']" "$(field "$json" 't["command"][-3:]')"
check "  with no secret"                 "0" "$(cad_has "$json" '--secret')"
json=$(with_fake boxsession_transport "codex-acp" w1 codex-acp b1 "$PROJECT" no plan)
status=$?
check "a level the agent cannot do is refused" "1" "$status"
check "  with nothing printed"           "" "$json"
check "  saying why"                     "1" "$(cad_has "$(message "$status")" 'Codex has no plan-only mode')"
set_developer agent-vm-home "/Volumes/Work/agent-vm"
json=$(with_fake boxsession_transport "claude-agent-acp" w1 claude-code-acp b1 "$PROJECT" no free)
check "Cadabra's store setting reaches the exec" "{'AGENT_VM_HOME': '/Volumes/Work/agent-vm'}" "$(field "$json" 't["env"]')"
set_developer agent-vm-home ""

section "a disposable box goes when its last window does"
fake_reset
box=$(with_fake boxsession_start w1 new:dev claude-code-acp "$PROJECT" no)
with_fake boxsession_registry_add w2 "$box" yes "$PROJECT" no
with_fake boxsession_release w1
check "one window of two closing keeps the box" "1" "$([ -f "$FAKE_AGENTVM_DIR/box-$box.json" ] && echo 1 || echo 0)"
check "  and the other's row"            "w2" "$(col 1 < "$REGISTRY")"
with_fake boxsession_release w2
check "the last one deletes it (stopped)" "0" "$([ -f "$FAKE_AGENTVM_DIR/box-$box.json" ] && echo 1 || echo 0)"
check "  and no row is left"             "" "$(/bin/cat "$REGISTRY")"
fake_reset
box=$(with_fake boxsession_start w1 new:dev claude-code-acp "$PROJECT" no)
/bin/cp "$FIXTURES/box-status-ready.json" "$FAKE_AGENTVM_DIR/box-$box.json"
with_fake boxsession_release w1
check "a running one is stopped by a job" "box stop $box --json" "$(wait_for_log 'box stop')"
fake_reset
with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" no >/dev/null
with_fake boxsession_release w1
check "a kept box is left alone"         "" "$(logged 'box stop')$(logged 'box delete')"
check "  its row removed"                "" "$(/bin/cat "$REGISTRY")"
with_fake boxsession_release no-such-window
check "a window with no row releases nothing" "0" "$?"

section "rows of a Cadabra that is gone are released at launch"
fake_reset
/bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-gone1.json"
/usr/bin/true &
live=$!
wait "$live"
/bin/mkdir -p "$(/usr/bin/dirname "$REGISTRY")"
printf 'wa\tgone1\tyes\t%s\tno\t%s\nwb\tb1\tno\t%s\tno\t%s\n' "$PROJECT" "$live" "$PROJECT" "$$" > "$REGISTRY"
with_fake boxsession_release_stale
check "the dead process's row goes"      "wb" "$(col 1 < "$REGISTRY")"
check "  and its disposable box with it" "0" "$([ -f "$FAKE_AGENTVM_DIR/box-gone1.json" ] && echo 1 || echo 0)"

# engine <function> [args...]  ->  the function's status, then CHAT_ENGINE_CONFIG, from the chat
# engine library with agent-vm faked (the way test 93 calls it).
engine() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM
      . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.chat.engine.library.sh" >/dev/null 2>&1
      prefs="$OMCTEST_WORK/no-such-registry.plist"
      "$@" >/dev/null 2>&1
      e_status=$?
      printf '%s\n%s\n' "$e_status" "$CHAT_ENGINE_CONFIG" )
}

section "where an agent runs, and its level, are kept per agent"
cad_reset
check "an agent with no choice runs on this Mac" "mac"  "$(cad_call acp_agent_run_in claude-code-acp)"
check "  and would work freely in a box"         "free" "$(cad_call acp_agent_level claude-code-acp)"
cad_call acp_agent_set_run_in claude-code-acp new:dev
check "a disposable box is stored"               "0|new:dev" "$?|$(cad_call acp_agent_run_in claude-code-acp)"
cad_call acp_agent_set_run_in "custom:3" box:b1
check "a saved agent's id is a key too"          "box:b1" "$(cad_call acp_agent_run_in "custom:3")"
check "  and the other agent kept its own"       "new:dev" "$(cad_call acp_agent_run_in claude-code-acp)"
cad_call acp_agent_set_level claude-code-acp plan
check "a level is stored"                        "plan" "$(cad_call acp_agent_level claude-code-acp)"
cad_call acp_agent_set_run_in claude-code-acp elsewhere
check "a place of another form is refused"       "2|new:dev" "$?|$(cad_call acp_agent_run_in claude-code-acp)"
cad_call acp_agent_set_level claude-code-acp yolo
check "a level of another value is refused"      "2" "$?"
cad_call acp_agent_set_run_in "a/b" mac
check "an id that would be a path is refused"    "2" "$?"
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
check "storing the agent leaves its place alone" "new:dev" "$(cad_call acp_agent_run_in claude-code-acp)"

section "chat init starts the agent's box and hands the element a transport into it"
fake_reset
cad_pb_set aichatv2_open_w1 1
cad_pb_set aichatv2_open_w2 1
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1; cad_call mcp_prefs_set_string servers/local/project "$PROJECT"
alerts_reset
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
check "it succeeds"                      "0" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
json=$(printf '%s\n' "$out" | /usr/bin/sed 1d)
box=$(col 2 < "$REGISTRY")
check "the transport runs agent-vm exec in that box" "1" "$(cad_has "$json" '"exec", "--box", "'"$box"'"')"
check "  sharing the project"            "1" "$(cad_has "$json" '"--project", "'"$PROJECT"'"')"
check "  starting in the free mode"      "1" "$(cad_has "$json" '"bypassPermissions"')"
check "the window's box is registered"   "w1${TAB}$box${TAB}yes" "$(/usr/bin/cut -f1-3 "$REGISTRY")"
check "no alert"                         "0" "$(alerts_count)"
fake_reset
out=$(engine chat_engine_box_transport w1 "my-agent --acp" custom new:dev false)
json=$(printf '%s\n' "$out" | /usr/bin/sed 1d)
check "an edited command runs as typed"  "1" "$(cad_has "$json" '"--", "my-agent", "--acp"')"
check "  in a box that reaches no host"  "0" "$(cad_has "$(logged 'box create')" '--allow')"

section "chat init refuses, says why, and leaves no box behind"
fake_reset
cad_reset
alerts_reset
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
check "no project folder refuses"        "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  saying where to choose one"     "1" "$(alerts_mention 'Agentic Session Tools')"
check "  before agent-vm made anything"  "" "$(logged 'box create')"
cad_call mcp_prefs_write_defaults >/dev/null 2>&1; cad_call mcp_prefs_set_string servers/local/project "$PROJECT"
fake_reset
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
alerts_reset
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
check "a box that cannot start refuses"  "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  with agent-vm's reason"         "1" "$(alerts_mention 'No virtual machine slot is free')"
check "  and no config"                  "" "$(printf '%s\n' "$out" | /usr/bin/sed 1d)"
check "  the made box is gone again"     "0" "$(/bin/ls "$FAKE_AGENTVM_DIR" | /usr/bin/grep -c '^box-cadabra-')"
check "  and so is its row"              "" "$(/bin/cat "$REGISTRY")"
fake_reset
cad_call acp_agent_set_level codex-acp plan
alerts_reset
out=$(engine chat_engine_box_transport w1 "codex-acp" codex-acp box:b1 false)
check "a level the agent cannot do refuses" "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  with the catalog's reason"      "1" "$(alerts_mention 'Codex has no plan-only mode')"
check "  and the window's row is released" "" "$(/bin/cat "$REGISTRY")"

section "a window closed while its box started gets no transport and keeps no box"
fake_reset
cad_pb_set aichatv2_open_w1 ""
alerts_reset
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
check "it refuses"                       "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  with no config"                 "" "$(printf '%s\n' "$out" | /usr/bin/sed 1d)"
check "  and no alert for a window that is gone" "0" "$(alerts_count)"
check "  the box it started is gone"     "0" "$(/bin/ls "$FAKE_AGENTVM_DIR" | /usr/bin/grep -c '^box-cadabra-')"
check "  and so is its row"              "" "$(/bin/cat "$REGISTRY")"
cad_pb_set aichatv2_open_w1 1

section "chat init refuses what it cannot run"
fake_reset
printf '0.1.0\n' > "$FAKE_AGENTVM_DIR/version"
alerts_reset
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
check "an agent-vm too old refuses"      "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  saying boxes cannot be used"    "1" "$(alerts_mention 'boxes cannot be used here')"
check "  before any box is made"         "" "$(logged 'box create')"
fake_reset
# The parent must exist first: plister's set replaces a value of any type, but cannot create a
# missing parent.
cad_call acp_agent_set_run_in claude-code-acp mac
"$cad_plister" set dict "$cad_settings" /agents/runIn/claude-code-acp >/dev/null 2>&1
check "  (the fixture: a dictionary where text belongs)" "dict" "$("$cad_plister" get type "$cad_settings" /agents/runIn/claude-code-acp 2>&1)"
check "a place stored as something else reads as damaged" "damaged" "$(cad_call acp_agent_run_in claude-code-acp)"
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
alerts_reset
out=$(engine chat_engine_transport_config w1 external "" false "claude-agent-acp")
check "  and does not run the agent on this Mac" "1|0" "$(printf '%s\n' "$out" | /usr/bin/head -1)|$(cad_has "$out" '"command"')"
check "  saying why"                     "1" "$(alerts_mention 'not a box choice')"
cad_call acp_agent_set_run_in claude-code-acp mac

section "the stored choice decides which path chat init takes"
fake_reset
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1; cad_call mcp_prefs_set_string servers/local/project "$PROJECT"
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp box:b1
out=$(engine chat_engine_transport_config w1 external "" false "claude-agent-acp")
check "an agent set to a box runs there" "1" "$(cad_has "$out" '"exec", "--box", "b1"')"
cad_call acp_agent_set_run_in claude-code-acp mac
fake_reset
out=$(engine chat_engine_transport_config w2 external "" false "claude-agent-acp")
check "one set to this Mac runs here"    "0|0" "$(printf '%s\n' "$out" | /usr/bin/head -1)|$(cad_has "$out" '"exec"')"
check "  with agent-vm never run"        "0" "$([ -f "$FAKE_AGENTVM_DIR/log" ] && echo 1 || echo 0)"

section "quitting releases this Cadabra's rows and no other's"
fake_reset
/bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-mine1.json"
/bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-theirs1.json"
/bin/mkdir -p "$(/usr/bin/dirname "$REGISTRY")"
printf 'wa\tmine1\tyes\t%s\tno\t%s\nwb\ttheirs1\tyes\t%s\tno\t%s\n' "$PROJECT" "${OMC_APP_PROCESS_ID:-1}" "$PROJECT" "$$" > "$REGISTRY"
with_fake boxsession_release_own
check "this process's row goes"          "wb" "$(col 1 < "$REGISTRY")"
check "  and its disposable box"         "0|1" "$([ -f "$FAKE_AGENTVM_DIR/box-mine1.json" ] && echo 1 || echo 0)|$([ -f "$FAKE_AGENTVM_DIR/box-theirs1.json" ] && echo 1 || echo 0)"

omctest_end
