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
fake_reset
/usr/bin/sed 's/"state" *: *"ready"/"state" : "running"/' "$FIXTURES/box-status-ready.json" > "$FAKE_AGENTVM_DIR/box-b1.json"
box=$(with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" no)
check "  nor one agent-vm 0.2.18 calls running" "b1|" "$box|$(logged 'box start')"
check "  and the full VM slots do not refuse it: it is one of them" "0" "$(cad_has "$(/bin/cat "$FAKE_AGENTVM_DIR/log")" 'doctor')"

fake_reset
/usr/bin/sed 's/"stopped"/"starting"/' "$FIXTURES/box-status-stopped.json" > "$FAKE_AGENTVM_DIR/box-b1.json"
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
box=$(with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" no)
check "a box that is starting is waited for" "b1|box start b1$owner_args --json" "$box|$(logged 'box start')"
check "  without the slot check"         "0" "$(cad_has "$(/bin/cat "$FAKE_AGENTVM_DIR/log")" 'doctor')"
fake_reset
/usr/bin/sed 's/"stopped"/"stopping"/' "$FIXTURES/box-status-stopped.json" > "$FAKE_AGENTVM_DIR/box-b1.json"
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
box=$(with_fake boxsession_start w1 box:b1 claude-code-acp "$PROJECT" no)
check "a box that is stopping is started again by agent-vm" "b1|box start b1$owner_args --json" "$box|$(logged 'box start')"
check "  also without the slot check"    "0" "$(cad_has "$(/bin/cat "$FAKE_AGENTVM_DIR/log")" 'doctor')"

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

section "the transport runs the agent in the box, with the key chosen for it"
fake_reset
cad_reset
/bin/cp "$FIXTURES/secret-list.json" "$FAKE_AGENTVM_DIR/secret-list.json"
json=$(with_fake boxsession_transport "claude-agent-acp" w1 claude-code-acp b1 "$PROJECT" no free)
check "the command is agent-vm exec in the box" "['$FAKE', 'exec', '--box', 'b1', '--project', '$PROJECT']" "$(field "$json" 't["command"][:6]')"
check "  with no key when none is chosen, though the Keychain holds one" "0" "$(cad_has "$json" '--secret')"
check "  starting in the free mode"      "{'mode': 'bypassPermissions'}" "$(field "$json" 't["sessionConfig"]')"
check "  with no store setting"          "False" "$(field "$json" '"env" in t')"
cad_call acp_agent_set_secret claude-code-acp CLAUDE_CODE_OAUTH_TOKEN
json=$(with_fake boxsession_transport "claude-agent-acp" w1 claude-code-acp b1 "$PROJECT" no free)
check "the chosen key is passed by name" "1" "$(cad_has "$json" '"--secret", "CLAUDE_CODE_OAUTH_TOKEN"')"
check "  and only that one"              "0" "$(cad_has "$json" 'ANTHROPIC_API_KEY')"
cad_call acp_agent_set_secret codex-acp OPENAI_API_KEY
json=$(with_fake boxsession_transport "codex-acp" w1 codex-acp b1 "$PROJECT" yes ask)
check "Codex gets the key chosen for it" "1" "$(cad_has "$json" '"--secret", "OPENAI_API_KEY"')"
check "  and the read-only share"        "1" "$(cad_has "$json" '"--read-only"')"
check "opencode gets no key chosen for another agent" "none" "$(cad_call acp_agent_secret opencode)"

section "a key chosen for the agent that cannot be honored is refused, never dropped"
cad_call acp_agent_set_secret claude-code-acp ANTHROPIC_API_KEY
json=$(with_fake boxsession_transport "claude-agent-acp" w1 claude-code-acp b1 "$PROJECT" no free)
status=$?
check "a key the Keychain does not hold refuses" "1|" "$status|$json"
check "  naming the key and where to store it" "1" "$(cad_has "$(message "$status")" 'Anthropic API key (ANTHROPIC_API_KEY), is not in the Keychain. Store it with Keys...')"
cad_call acp_agent_set_secret claude-code-acp OPENAI_API_KEY
json=$(with_fake boxsession_transport "claude-agent-acp" w1 claude-code-acp b1 "$PROJECT" no free)
status=$?
check "a key the agent does not use refuses" "1|" "$status|$json"
check "  saying so"                      "1" "$(cad_has "$(message "$status")" 'does not use the key OPENAI_API_KEY')"
"$cad_plister" set dict "$cad_settings" /agents/secret/claude-code-acp >/dev/null 2>&1
check "  (the fixture: a dictionary where text belongs)" "damaged" "$(cad_call acp_agent_secret claude-code-acp)"
json=$(with_fake boxsession_transport "claude-agent-acp" w1 claude-code-acp b1 "$PROJECT" no free)
status=$?
check "a choice that cannot be read refuses" "1|" "$status|$json"
check "  saying so"                      "1" "$(cad_has "$(message "$status")" 'cannot be read')"
cad_call acp_agent_set_secret claude-code-acp CLAUDE_CODE_OAUTH_TOKEN
printf 'Keychain is locked\n' > "$FAKE_AGENTVM_DIR/fail-secret-list"
json=$(with_fake boxsession_transport "claude-agent-acp" w1 claude-code-acp b1 "$PROJECT" no free)
status=$?
check "a Keychain that cannot be listed refuses" "1|" "$status|$json"
check "  with agent-vm's reason"         "1" "$(cad_has "$(message "$status")" 'Keychain is locked')"
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-secret-list"
check "the setter refuses a name agent-vm would" "2|2|2" "$(cad_call acp_agent_set_secret claude-code-acp 1ABC; printf '%s' $?)|$(cad_call acp_agent_set_secret claude-code-acp 'A-B'; printf '%s' $?)|$(cad_call acp_agent_set_secret claude-code-acp ''; printf '%s' $?)"
check "  and keeps the choice it had"    "CLAUDE_CODE_OAUTH_TOKEN" "$(cad_call acp_agent_secret claude-code-acp)"
cad_call acp_agent_set_secret claude-code-acp none
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

section "closing the last window of a running kept box asks whether to stop it"
# kept_box <state> <programs> [owner pid] - box b1's status as agent-vm 0.3.8 answers it, and a
# registry row for window w1 on it, as chat init leaves one.
kept_box() {
    if [ -n "${3:-}" ]; then
        /usr/bin/sed -e "s/\"state\": \"ready\"/\"state\": \"$1\"/" -e "s/\"activeExecs\": 1,/\"activeExecs\": $2,/" \
            -e "s/\"pid\": 44847,/\"ownerPid\": $3, \"pid\": 44847,/" \
            "$FIXTURES/box-status-ready.json" > "$FAKE_AGENTVM_DIR/box-b1.json"
    else
        /usr/bin/sed -e "s/\"state\": \"ready\"/\"state\": \"$1\"/" -e "s/\"activeExecs\": 1,/\"activeExecs\": $2,/" \
            "$FIXTURES/box-status-ready.json" > "$FAKE_AGENTVM_DIR/box-b1.json"
    fi
    /bin/mkdir -p "$(/usr/bin/dirname "$REGISTRY")"
    printf 'w1\tb1\tno\t%s\tno\t%s\n' "$PROJECT" "$$" > "$REGISTRY"
    alerts_reset
    alert_answers_reset
}
# stop_jobs  ->  how many stop jobs box b1 has had, from the job list (a job starts detached, so
# its absence from the fake's log right after the call proves nothing).
stop_jobs() {
    cad_call_lib aichat.agentvm.library.sh agentvm_jobs | /usr/bin/awk -F'\t' '$2 == "box-stop" && $3 == "box:b1" { n++ } END { print n + 0 }'
}
fake_reset
kept_box running 0 999999
alert_answer 0
with_fake boxsession_close w1
check "it asks"                          "1" "$(alerts_mention 'Stop the AgentVM box b1?')"
check "  naming the slot and the memory" "1" "$(alerts_mention 'two virtual machine slots on this Mac and 4 GB of memory')"
check "  and that a box Cadabra did not start keeps running" "1" "$(alerts_mention 'Cadabra did not start it, so it keeps running')"
check "Stop Box stops it with a job"     "box stop b1 --json" "$(wait_for_log 'box stop')"
check "  and the row is gone"            "" "$(/bin/cat "$REGISTRY")"
fake_reset
kept_box running 0 999999
alert_answer 1
jobs_before=$(stop_jobs)
with_fake boxsession_close w1
check "Keep Running leaves it running"   "1|$jobs_before" "$(alerts_count)|$(stop_jobs)"
if [ -n "${OMC_APP_PROCESS_ID:-}" ]; then
    fake_reset
    kept_box starting 0 "$OMC_APP_PROCESS_ID"
    alert_answer 1
    with_fake boxsession_close w1
    check "a box this Cadabra started, still starting: asked too" "1" "$(alerts_mention 'Stop the AgentVM box b1?')"
    check "  saying Cadabra stops it at quit" "1" "$(alerts_mention 'Cadabra stops it when Cadabra quits')"
fi
fake_reset
kept_box running 2
alert_answer 0
jobs_before=$(stop_jobs)
with_fake boxsession_close w1
check "programs from elsewhere are named" "1" "$(alerts_mention '2 programs Cadabra did not start run in it right now')"
check "  and the default button keeps it" "$jobs_before" "$(stop_jobs)"
fake_reset
kept_box running 1
alert_answer 2
with_fake boxsession_close w1
check "  while the other one stops it"   "box stop b1 --json" "$(wait_for_log 'box stop')"
check "  one program, said once"         "1" "$(alerts_mention '1 program Cadabra did not start runs in it right now')"
fake_reset
kept_box running 1
alert_answer 1
jobs_before=$(stop_jobs)
with_fake boxsession_close w1
check "  and a cancel answer, as Escape might give, keeps it" "$jobs_before" "$(stop_jobs)"
fake_reset
kept_box running 0
printf 'w2\tb1\tno\t%s\tno\t%s\n' "$PROJECT" "$$" >> "$REGISTRY"
with_fake boxsession_close w1
check "no question while another window uses it" "0|w2" "$(alerts_count)|$(col 1 < "$REGISTRY")"
# A window that starts on the box after the close released w1: during the wait for the closing
# window's clients (close_while_w2_starts), or while the question is up (close_while_w2_asked,
# whose alert adds the row and answers Stop Box).
W2_ROW="w2${TAB}b1${TAB}no${TAB}$PROJECT${TAB}no${TAB}$$"
W2_ALERT="$OMCTEST_WORK/alert-opens-w2.sh"
printf '#!/bin/sh\nprintf "%%s\\n" "$W2_ROW" >> "$W2_REGISTRY"\nexit 0\n' > "$W2_ALERT"
/bin/chmod +x "$W2_ALERT"
close_while_w2_starts() {
    _boxsession_own_execs() { printf '%s\n' "$W2_ROW" >> "$REGISTRY"; echo 0; }
    boxsession_close w1
}
close_while_w2_asked() {
    W2_REGISTRY="$REGISTRY"
    export W2_ROW W2_REGISTRY
    alert="$W2_ALERT"
    boxsession_close w1
}
fake_reset
kept_box running 2
alert_answer 255
jobs_before=$(stop_jobs)
with_fake boxsession_close w1
check "an alert that failed keeps a box with programs from elsewhere" "1|$jobs_before" "$(alerts_count)|$(stop_jobs)"
fake_reset
kept_box running 0
jobs_before=$(stop_jobs)
with_fake close_while_w2_starts
check "a window that started on it meanwhile: no question" "0|$jobs_before" "$(alerts_count)|$(stop_jobs)"
fake_reset
kept_box running 0
jobs_before=$(stop_jobs)
with_fake close_while_w2_asked
check "one that started while it asked: Stop Box leaves it running" "$jobs_before" "$(stop_jobs)"
check "  and its row"                    "w2" "$(col 1 < "$REGISTRY")"
# Windows closing together: the handler that asks holds a claim on the box; another one asking
# meanwhile stays quiet, and a claim whose handler is gone is taken over and removed after.
CLAIM="$(/usr/bin/dirname "$REGISTRY")/box-stop-question-b1"
fake_reset
kept_box running 0
/bin/mkdir -p "$CLAIM"
printf '%s\n' "$$" > "$CLAIM/pid"
with_fake boxsession_close w1
check "no second question while another close asks" "0|" "$(alerts_count)|$(/bin/cat "$REGISTRY")"
/bin/rm -rf "$CLAIM"
/usr/bin/true &
gone=$!
wait "$gone"
fake_reset
kept_box running 0
/bin/mkdir -p "$CLAIM"
printf '%s\n' "$gone" > "$CLAIM/pid"
alert_answer 1
with_fake boxsession_close w1
check "a claim left by a handler that is gone is taken over" "1" "$(alerts_mention 'Stop the AgentVM box b1?')"
check "  and removed after"             "0" "$([ -d "$CLAIM" ] && echo 1 || echo 0)"
fake_reset
kept_box stopped 0
/bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-b1.json"
with_fake boxsession_close w1
check "no question for a stopped box"    "0" "$(alerts_count)"
fake_reset
alerts_reset
box=$(with_fake boxsession_start w1 new:dev claude-code-acp "$PROJECT" no)
with_fake boxsession_close w1
check "none for a disposable box, which just goes" "0|0" "$(alerts_count)|$([ -f "$FAKE_AGENTVM_DIR/box-$box.json" ] && echo 1 || echo 0)"
alert_answers_reset

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
check "  and the image it came from is stamped for the record" "$box${TAB}dev" "$(cad_pb_get aichatv2_boximage_w1)"
check "  which the record reads with the row" "$box${TAB}dev${TAB}yes${TAB}$PROJECT${TAB}no" "$(with_fake boxsession_meta_fields w1)"
check "no alert"                         "0" "$(alerts_count)"
fake_reset
cad_call acp_agent_set_read_only claude-code-acp yes
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
json=$(printf '%s\n' "$out" | /usr/bin/sed 1d)
check "a read-only choice reaches the transport" "1" "$(cad_has "$json" '"--read-only"')"
check "  the warm-up"                    "1" "$(cad_has "$(logged 'exec --box')" '--read-only')"
check "  and the registry"               "yes" "$(col 5 < "$REGISTRY")"
cad_call acp_agent_set_read_only claude-code-acp no
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
fake_reset
cad_call acp_agent_set_read_only claude-code-acp no
"$cad_plister" set dict "$cad_settings" /agents/readOnly/claude-code-acp >/dev/null 2>&1
alerts_reset
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
check "a share mode that cannot be read refuses" "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  saying where to choose it"      "1" "$(alerts_mention 'Choose it again in Agentic Session Tools')"
check "  before agent-vm made anything"  "" "$(logged 'box create')"
cad_call acp_agent_set_read_only claude-code-acp no
fake_reset
cad_call acp_agent_set_secret claude-code-acp ANTHROPIC_API_KEY
alerts_reset
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
check "a chosen key the Keychain does not hold refuses" "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  saying where to store it"       "1" "$(alerts_mention 'Store it with Keys...')"
check "  before agent-vm made anything"  "" "$(logged 'box create')"
check "  and with no row"                "" "$(/bin/cat "$REGISTRY")"
cad_call acp_agent_set_secret claude-code-acp none

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
check "  saying why"                     "1" "$(alerts_mention 'not an AgentVM box choice')"
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

section "the box line names the box and counts its connections since the agent started"
# netlog_fixture - a network log with one entry before the agent started (09:00) and five after:
# one host reached twice, another once, one refused and one whose connection failed.
netlog_fixture() {
    /bin/cat > "$FAKE_AGENTVM_DIR/netlog.json" <<'JSONEOF'
[
  {"decision": "denied", "host": "old.example", "method": "CONNECT", "port": 443, "reason": "not in the allowlist", "time": "2026-09-27T09:00:00Z"},
  {"decision": "allowed", "host": "api.anthropic.com", "method": "CONNECT", "port": 443, "rule": "pack:anthropic", "time": "2026-09-27T10:01:00Z"},
  {"decision": "allowed", "host": "api.anthropic.com", "method": "CONNECT", "port": 443, "rule": "pack:anthropic", "time": "2026-09-27T10:02:00Z"},
  {"decision": "allowed", "host": "registry.npmjs.org", "method": "CONNECT", "port": 443, "rule": "registry.npmjs.org", "time": "2026-09-27T10:03:00Z"},
  {"decision": "denied", "host": "bag.itunes.apple.com", "method": "CONNECT", "port": 443, "reason": "not in the allowlist", "time": "2026-09-27T10:04:00Z"},
  {"decision": "failed", "host": "down.example", "method": "CONNECT", "port": 443, "reason": "connection refused", "time": "2026-09-27T10:05:00Z"}
]
JSONEOF
}
# line_title / line_help  ->  the last text or tooltip set on the line (the journal flattens
# the tooltip's line breaks to spaces). The text is the Label's value (a bare-value call, which
# the journal records as the value alone): a Label shows its value, which a later
# omc_set_property title does not change.
line_title() { cad_journal 544 | /usr/bin/grep -v '^omc_' | /usr/bin/tail -1; }
line_help() { cad_journal 544 | /usr/bin/sed -n 's/^omc_set_property help //p' | /usr/bin/tail -1; }
since="2026-09-27T10:00:00Z"
fake_reset
netlog_fixture
check "the counts: hosts reached, refused and failed, each host once, none before the start" \
    "2${TAB}1${TAB}1${TAB}api.anthropic.com,registry.npmjs.org${TAB}bag.itunes.apple.com${TAB}down.example${TAB}no" \
    "$(with_fake boxsession_net_counts b1 "$since")"
check "  read from the log's last entries only" "1" "$(cad_has "$(logged 'box netlog')" 'box netlog b1 --last 999')"
# The fake answers with the whole fixture whatever --last says, so its six entries stand for
# "the last six" here.
check "a full read not reaching back to the start is marked partial" "yes" \
    "$(with_fake eval 'boxsession_line_netlog_last=6; boxsession_net_counts b1 2026-09-27T08:00:00Z' | col 7)"
check "  one reaching back past it is not" "no" \
    "$(with_fake eval 'boxsession_line_netlog_last=6; boxsession_net_counts b1 2026-09-27T09:30:00Z' | col 7)"
check "  nor is a log shorter than the read" "no" \
    "$(with_fake eval 'boxsession_line_netlog_last=7; boxsession_net_counts b1 2026-09-27T08:00:00Z' | col 7)"
printf '[]\n' > "$FAKE_AGENTVM_DIR/netlog.json"
check "an empty log counts nothing" "0${TAB}0${TAB}0${TAB}-${TAB}-${TAB}-${TAB}no" "$(with_fake boxsession_net_counts b1 "$since")"

cad_pb_set aichatv2_open_w1 1
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1; cad_call mcp_prefs_set_string servers/local/project "$PROJECT"
fake_reset
cad_journal_reset
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
box=$(col 2 < "$REGISTRY")
check "chat init puts the line into its slot" "1" "$(cad_has "$(cad_journal 543)" 'omc_insert_element {"type":"HStack","id":545')"
check "  a row with the line and its Network... button" "1|1" "$(cad_has "$(cad_journal 543)" '{"type":"Label","id":544')|$(cad_has "$(cad_journal 543)" '"actionID":"aichat.chat.box.network"')"
check "  naming the disposable box and its image" "Disposable AgentVM box $box from dev - no connections yet" "$(line_title)"
check "  as the Label's value, which is what it shows" "0" "$(cad_has "$(cad_journal 544)" 'omc_set_property title')"
check "  and remembers the box and the line for the refreshes" "$box${TAB}Disposable AgentVM box $box from dev" \
    "$(cad_pb_get aichatv2_boxline_w1 | /usr/bin/cut -f1,3)"
stamp_since=$(cad_pb_get aichatv2_boxline_w1 | /usr/bin/cut -f2)
check "  with the moment it started, as agent-vm writes times" "1" \
    "$(printf '%s\n' "$stamp_since" | /usr/bin/grep -c '^20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z$')"
fake_reset
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
cad_journal_reset
out=$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)
check "a box that cannot start puts no line up" "0" "$(cad_writes 543)"

fake_reset
netlog_fixture
printf 'w1\tb1\tno\t%s\tyes\t1\n' "$PROJECT" > "$REGISTRY"
check "a kept box's line says so, and a read-only share" "Kept AgentVM box b1 (stays running), project read-only" "$(with_fake boxsession_line_head w1)"
cad_pb_set aichatv2_boxline_w1 "b1${TAB}$since${TAB}AgentVM box b1, project read-only"
cad_journal_reset
with_fake boxsession_line_refresh w1
check "a refresh restates the counts" "AgentVM box b1, project read-only - 2 hosts reached, 1 refused, 1 failed" "$(line_title)"
check "  and names the hosts in the tooltip" \
    "Reached: api.anthropic.com, registry.npmjs.org Refused: bag.itunes.apple.com Failed: down.example Counted for every program in AgentVM box b1 since the agent started, each connection when it opens. Programs in the box reach only the hosts its rules allow; agent-vm box netlog b1 --denied lists the refused ones. A kept box keeps running when its chat windows close, holding one of the two virtual machine slots on this Mac, unless you stop it: closing the last window that uses it asks." \
    "$(line_help)"
/bin/cat > "$FAKE_AGENTVM_DIR/netlog.json" <<'JSONEOF'
[
  {"decision": "denied", "host": "h1.example", "method": "CONNECT", "port": 443, "time": "2026-09-27T10:01:00Z"},
  {"decision": "denied", "host": "h2.example", "method": "CONNECT", "port": 443, "time": "2026-09-27T10:01:00Z"},
  {"decision": "denied", "host": "h3.example", "method": "CONNECT", "port": 443, "time": "2026-09-27T10:01:00Z"},
  {"decision": "denied", "host": "h4.example", "method": "CONNECT", "port": 443, "time": "2026-09-27T10:01:00Z"},
  {"decision": "denied", "host": "h5.example", "method": "CONNECT", "port": 443, "time": "2026-09-27T10:01:00Z"},
  {"decision": "denied", "host": "h6.example", "method": "CONNECT", "port": 443, "time": "2026-09-27T10:01:00Z"},
  {"decision": "denied", "host": "h7.example", "method": "CONNECT", "port": 443, "time": "2026-09-27T10:01:00Z"},
  {"decision": "denied", "host": "h8.example", "method": "CONNECT", "port": 443, "time": "2026-09-27T10:01:00Z"}
]
JSONEOF
cad_journal_reset
with_fake boxsession_line_refresh w1
check "only refusals: no host reached" "AgentVM box b1, project read-only - no host reached, 8 refused" "$(line_title)"
check "  and a long list is cut short" "1" "$(cad_has "$(line_help)" 'h6.example and 2 more Counted')"
printf '1\n' > "$FAKE_AGENTVM_DIR/exit"
printf 'Error: no box b1; `agent-vm box list` shows the existing ones\n' > "$FAKE_AGENTVM_DIR/stderr"
cad_journal_reset
with_fake boxsession_line_refresh w1
/bin/rm -f "$FAKE_AGENTVM_DIR/exit" "$FAKE_AGENTVM_DIR/stderr"
check "a log agent-vm cannot give says so" "AgentVM box b1, project read-only - network log unavailable" "$(line_title)"
check "  with agent-vm's reason in the tooltip" "1" "$(cad_has "$(line_help)" 'no box b1')"
cad_pb_set aichatv2_boxline_w2 ""
cad_journal_reset
with_fake boxsession_line_refresh w2
check "a window without a line is left alone" "0" "$(cad_writes 544)"
with_fake boxsession_release w1
check "releasing the window forgets its line" "" "$(cad_pb_get aichatv2_boxline_w1)"

section "the entry handler refreshes the line after a message, in the background"
fake_reset
netlog_fixture
win="$OMC_ACTIONUI_WINDOW_UUID"
printf '%s\tb1\tno\t%s\tno\t1\n' "$win" "$PROJECT" > "$REGISTRY"
cad_pb_set "aichatv2_boxline_$win" "b1${TAB}$since${TAB}AgentVM box b1"
cad_pb_set "aichatv2_session_$win" "entry-test"
cad_journal_reset
# entry <type>  ->  the entry handler run for one finalized entry of that type.
entry() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM
      export OMC_ACTIONUI_TRIGGER_CONTEXT="{\"sequence\":2,\"type\":\"$1\",\"id\":\"e$1\",\"data\":{\"type\":\"$1\",\"message\":{\"role\":\"agent\",\"text\":\"done\"}}}"
      omc_run aichat.chat.entry ) >/dev/null 2>&1
}
entry usage
/bin/sleep 1
check "an entry that is not a message does not read the log" "" "$(logged 'box netlog' 2>/dev/null)"
entry message
w_left=50
# The tooltip is the refresh's last write: waiting for it leaves no child writing after this file ends.
while [ -z "$(line_help)" ] && [ "$w_left" -gt 0 ]; do w_left=$((w_left - 1)); /bin/sleep 0.1; done
check "a message does"                 "AgentVM box b1 - 2 hosts reached, 1 refused, 1 failed" "$(line_title)"
/bin/rm -f "$REGISTRY"
cad_pb_set "aichatv2_boxline_$win" ""
cad_pb_set "aichatv2_session_$win" ""

section "the box line counts the permission prompts its programs met, and tells of a new one once"
# execlog_fixture [stopped]  ->  an exec log: a run before the agent started (a prompt not
# counted), the agent's run with two prompts, and a later run meeting one of them again.
execlog_fixture() {
    /bin/cat > "$FAKE_AGENTVM_DIR/execlog.json" <<JSONEOF
[
  {"argv": ["/usr/bin/true"], "id": "a0", "prompts": ["the Desktop folder"], "started": "2026-09-27T09:00:00Z", "status": 0, "user": "agent"},
  {"argv": ["claude-agent-acp"], "id": "a1", "prompts": ["the Downloads folder", "a Keychain item"], "started": "2026-09-27T10:00:30Z", "stoppedOnPrompt": ${1:-true}, "user": "agent"},
  {"argv": ["/bin/ls"], "id": "a2", "prompts": ["the Downloads folder"], "started": "2026-09-27T10:02:00Z", "status": 1, "user": "agent"}
]
JSONEOF
}
PBOX=cadabra-spike
fake_reset
/bin/cp "$FIXTURES/box-status-ready.json" "$FAKE_AGENTVM_DIR/box-$PBOX.json"
netlog_fixture
execlog_fixture
check "the prompts since the agent started, each once, in order, with whether the program was stopped" \
    "the Downloads folder${TAB}true
a Keychain item${TAB}true" "$(with_fake boxsession_prompts "$PBOX" "$since")"
check "  read from the exec log's last runs" "1" "$(cad_has "$(logged 'box execlog')" "box execlog $PBOX --last 200")"
cad_pb_set aichatv2_boxline_w1 "$PBOX${TAB}$since${TAB}AgentVM box $PBOX"
cad_pb_set aichatv2_boxprompts_w1 ""
cad_journal_reset
alerts_reset
with_fake boxsession_line_refresh w1
check "the line counts them" "AgentVM box $PBOX - 2 hosts reached, 1 refused, 1 failed - 2 permission prompts" "$(line_title)"
check "  and the tooltip names them first" "1" "$(cad_has "$(line_help)" 'Permission prompts nobody in the AgentVM box could answer: the Downloads folder, a Keychain item Reached: api.anthropic.com')"
check "an alert tells of them"           "1" "$(alerts_count)"
check "  naming what they were for"      "1" "$(alerts_mention 'needed macOS permission to use the Downloads folder, a Keychain item')"
check "  that agent-vm stopped the program" "1" "$(alerts_mention 'so agent-vm stopped the program')"
check "  and the image to give Full Disk Access" "1" "$(alerts_mention 'give the image dev-agents Full Disk Access')"
check "  and, for the Keychain item, logging in inside a kept box" "1" "$(alerts_mention 'Log in with the agent inside a kept box')"
with_fake boxsession_line_refresh w1
check "the next refresh tells nothing again" "1" "$(alerts_count)"
check "  and still counts them"          "1" "$(cad_has "$(line_title)" '- 2 permission prompts')"
/bin/cat > "$FAKE_AGENTVM_DIR/execlog.json" <<'JSONEOF'
[
  {"argv": ["claude-agent-acp"], "id": "a1", "prompts": ["the Downloads folder", "a Keychain item", "the microphone"], "started": "2026-09-27T10:00:30Z", "user": "agent"}
]
JSONEOF
alerts_reset
with_fake boxsession_line_refresh w1
check "a new prompt is told"             "1" "$(alerts_count)"
check "  alone"                          "1|0" "$(alerts_mention 'permission to use the microphone.')|$(alerts_mention 'Downloads')"
check "  and a program not stopped may still wait" "1" "$(alerts_mention 'the program may wait until it is answered')"
check "  with no Keychain advice for a prompt that is not one" "1|0" "$(alerts_mention 'Full Disk Access')|$(alerts_mention 'Keychain item belongs')"
/bin/cat > "$FAKE_AGENTVM_DIR/execlog.json" <<'JSONEOF'
[
  {"argv": ["claude-agent-acp"], "id": "a1", "prompts": ["the Downloads folder", "a Keychain item", "the microphone"], "started": "2026-09-27T10:00:30Z", "user": "agent"},
  {"argv": ["/bin/ls"], "id": "a3", "prompts": ["the Documents folder"], "started": "2026-09-27T10:05:00Z", "status": 1, "user": "agent"}
]
JSONEOF
alerts_reset
with_fake boxsession_line_refresh w1
check "a later run's prompt is told"     "1|1" "$(alerts_count)|$(alerts_mention 'permission to use the Documents folder.')"
/bin/cat > "$FAKE_AGENTVM_DIR/execlog.json" <<'JSONEOF'
[
  {"argv": ["claude-agent-acp"], "id": "a1", "prompts": ["the Downloads folder", "a Keychain item", "the microphone", "the camera"], "started": "2026-09-27T10:00:30Z", "stoppedOnPrompt": true, "user": "agent"},
  {"argv": ["/bin/ls"], "id": "a3", "prompts": ["the Documents folder"], "started": "2026-09-27T10:05:00Z", "status": 1, "user": "agent"}
]
JSONEOF
alerts_reset
with_fake boxsession_line_refresh w1
check "then a new prompt of an earlier run is told, listed before it" "1|1|0" \
    "$(alerts_count)|$(alerts_mention 'permission to use the camera.')|$(alerts_mention 'Documents')"
check "  with that run stopped"          "1" "$(alerts_mention 'so agent-vm stopped the program')"
check "  and every prompt told is kept"  "5" "$(cad_pb_get aichatv2_boxprompts_w1 | /usr/bin/awk -F'\t' '{ print NF }')"
/bin/cat > "$FAKE_AGENTVM_DIR/execlog.json" <<'JSONEOF'
[
  {"argv": ["claude-agent-acp"], "id": "a1", "prompts": ["a Keychain item"], "started": "2026-09-27T10:00:30Z", "stoppedOnPrompt": true, "user": "agent"}
]
JSONEOF
cad_pb_set aichatv2_boxprompts_w1 ""
alerts_reset
with_fake boxsession_line_refresh w1
check "a Keychain prompt alone gets the login advice only" "1|0" "$(alerts_mention 'Keychain item belongs')|$(alerts_mention 'Full Disk Access')"
fake_reset
/bin/cp "$FIXTURES/box-status-ready.json" "$FAKE_AGENTVM_DIR/box-$PBOX.json"
netlog_fixture
printf '[]\n' > "$FAKE_AGENTVM_DIR/execlog.json"
cad_pb_set aichatv2_boxprompts_w1 ""
cad_journal_reset
alerts_reset
with_fake boxsession_line_refresh w1
check "no prompt: nothing on the line"   "AgentVM box $PBOX - 2 hosts reached, 1 refused, 1 failed" "$(line_title)"
check "  and no alert"                   "0" "$(alerts_count)"
execlog_fixture
printf 'the exec log is damaged\n' > "$FAKE_AGENTVM_DIR/fail-box-execlog"
cad_journal_reset
with_fake boxsession_line_refresh w1
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-box-execlog"
check "an exec log agent-vm cannot give leaves the network part" "AgentVM box $PBOX - 2 hosts reached, 1 refused, 1 failed" "$(line_title)"
check "  with no alert"                  "0" "$(alerts_count)"
printf '1\n' > "$FAKE_AGENTVM_DIR/exit"
cad_journal_reset
with_fake boxsession_line_refresh w1
/bin/rm -f "$FAKE_AGENTVM_DIR/exit"
check "neither log: the line says the network log is unavailable" "AgentVM box $PBOX - network log unavailable" "$(line_title)"
cad_pb_set aichatv2_boxprompts_w1 "2"
printf 'w1\t%s\tno\t%s\tno\t1\n' "$PBOX" "$PROJECT" > "$REGISTRY"
with_fake boxsession_line_show w1 "$PBOX"
check "a new line forgets the prompts told" "" "$(cad_pb_get aichatv2_boxprompts_w1)"
cad_pb_set aichatv2_boxprompts_w1 "2"
with_fake boxsession_release w1
check "  and so does a release"          "" "$(cad_pb_get aichatv2_boxprompts_w1)"
/bin/rm -f "$REGISTRY"

omctest_end
