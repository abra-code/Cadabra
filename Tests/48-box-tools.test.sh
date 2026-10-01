#!/bin/sh
# Tests/48-box-tools.test.sh - a local model's MCP servers in an agent-vm box, the model on this
# Mac (the plan's D11): copying Cadabra's tools into the box, starting a box for them, the MCP
# config's box mode, and chat init's path. agent-vm is fake_agent_vm.sh, as in tests 45-48; with
# its exec-run switch, `exec` runs the program on this Mac with the scratch $HOME as the box
# user's home, so the real copy script and the real servers run.
#
# Needs the sandbox off (a release's stop job runs detached through agentvm_job.py, which uses
# ps). POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.boxsession.library.sh
FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
export FAKE_AGENTVM_DIR
REGISTRY="$HOME/Library/Application Support/Cadabra/box-sessions.tsv"
TOOLS_ROOT="$HOME/Library/Application Support/Cadabra/Tools"
PYCACHE="$HOME/Library/Caches/Cadabra/pycache"
PROJECT="$OMCTEST_WORK/src/app"
TAB=$(printf '\t')
/bin/mkdir -p "$PROJECT"

unset AGENT_VM_HOME
# No real agent-vm here either (lib.test.cadabra.sh); every call below goes through with_fake or engine.
CADABRA_AGENT_VM="$OMCTEST_WORK/no-agent-vm-in-tests"
CADABRA_BOXWATCH_EVERY=1
CADABRA_BOXWATCH_FOR=1
export CADABRA_BOXWATCH_EVERY CADABRA_BOXWATCH_FOR

with_fake() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib "$LIB" "$@" )
}
message() { cad_call_lib "$LIB" agentvm_last_error "$1"; }
col() { /usr/bin/cut -f"$1"; }
logged() { /usr/bin/grep "^$1" "$FAKE_AGENTVM_DIR/log"; }
# logged_count <prefix>  ->  how many invocations started so; 0 when agent-vm never ran.
logged_count() {
    if [ -f "$FAKE_AGENTVM_DIR/log" ]; then
        /usr/bin/grep -c "^$1" "$FAKE_AGENTVM_DIR/log"
    else
        printf '0\n'
    fi
}

# fake_reset - a fake with a stopped box b1, a free VM slot, no registry, exec running programs.
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
    /bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-b1.json"
    /usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
    printf '0\n' > "$FAKE_AGENTVM_DIR/delay"
    : > "$FAKE_AGENTVM_DIR/exec-run"
    /bin/rm -f "$REGISTRY"
}

# prefs_reset [internet] - the MCP settings at their defaults with the project set, and the box
# pane's Internet as given (its default, off, when not given).
prefs_reset() {
    cad_reset
    cad_call mcp_prefs_write_defaults >/dev/null 2>&1
    cad_call mcp_prefs_set_string servers/local/project "$PROJECT"
    box_set internet "${1:-false}"
}

# box_set <name> <true|false> - one setting of the box pane.
box_set() {
    cad_call_lib aichat.mcp.servers.library.sh mcp_box_set_setting "$1" "$2"
}

engine() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM
      . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.chat.engine.library.sh" >/dev/null 2>&1
      prefs="$OMCTEST_WORK/no-such-registry.plist"
      "$@" >/dev/null 2>&1
      e_status=$?
      printf '%s\n%s\n' "$e_status" "$CHAT_ENGINE_CONFIG" )
}

# server <config> <name> <python expression over s>  ->  one value of a server entry of the MCP
# config, printed by Python.
server() {
    "$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -c 'import json, sys
servers = {s["name"]: s for s in json.load(open(sys.argv[1]))["servers"]}
s = servers.get(sys.argv[2])
print("absent" if s is None else eval(sys.argv[3]))' "$1" "$2" "$3" 2>&1
}

TOOLS_ID=$(with_fake boxsession_tools_id)

# -----------------------------------------------------------------------------------------
section "the tools' folder is named for Cadabra's version and a digest of its files"
case "$TOOLS_ID" in
    *-[0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef]) named=yes ;;
    *) named="no: $TOOLS_ID" ;;
esac
check "<version>-<12 hex digits>"         "yes" "$named"
check "  the version is Cadabra's"        "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$OMC_APP_BUNDLE_PATH/Contents/Info.plist")" "${TOOLS_ID%-*}"
check "  the same on every call"          "$TOOLS_ID" "$(with_fake boxsession_tools_id)"

section "the tools are copied into a running box once, then found there"
fake_reset
/bin/rm -rf "$TOOLS_ROOT" "$PYCACHE"
/bin/mkdir -p "$TOOLS_ROOT/0.9-000000000000/Support" "$PYCACHE$TOOLS_ROOT/0.9-000000000000/Library"
row=$(with_fake boxsession_tools_copy b1)
status=$?
dir="$TOOLS_ROOT/$TOOLS_ID"
check "it copies"                         "0" "$status"
check "  answering the folder and the bytecode cache" "$dir${TAB}$PYCACHE" "$row"
check "  replay, pdfutil and the Python servers are there" "yes|yes|yes|yes" \
    "$([ -x "$dir/Support/replay" ] && echo yes)|$([ -x "$dir/Support/pdfutil" ] && echo yes)|$([ -x "$dir/Library/Python/bin/python3" ] && echo yes)|$([ -d "$dir/Library/Packages/mcp_server_time" ] && echo yes)"
check "  with replay's profile for the box" "yes" "$([ -f "$dir/Resources/replay-box-sandbox.json" ] && echo yes)"
check "  compiled into the cache"         "yes" "$([ -d "$PYCACHE" ] && echo yes)"
check "  marked complete"                 "yes" "$([ -f "$dir/.cadabra-tools-complete" ] && echo yes)"
check "  a copy of another build is gone, with its bytecode" "no|no" "$([ -d "$TOOLS_ROOT/0.9-000000000000" ] && echo yes || echo no)|$([ -d "$PYCACHE$TOOLS_ROOT/0.9-000000000000" ] && echo yes || echo no)"
check "  while this copy's bytecode is there" "yes" "$([ -d "$PYCACHE$TOOLS_ROOT/$TOOLS_ID/Library" ] && echo yes || echo no)"
check "  two programs ran in the box, neither with the project" "2|0" \
    "$(logged_count 'exec --box b1 -- /bin/sh -c')|$(logged_count 'exec --box b1 --project')"
: > "$FAKE_AGENTVM_DIR/log"
row=$(with_fake boxsession_tools_copy b1)
check "a second window finds the copy"    "0|$dir${TAB}$PYCACHE" "$?|$row"
check "  and copies nothing"              "1" "$(logged_count 'exec --box b1')"
check "  the lock is released"            "no" "$([ -d "$HOME/Library/Application Support/Cadabra/box-tools-b1.lock" ] && echo yes || echo no)"

section "a copy that fails leaves agent-vm's reason, and no lock"
fake_reset
printf '%s' 'box b1 is not running; start it with agent-vm box start b1' > "$FAKE_AGENTVM_DIR/exec-error"
row=$(with_fake boxsession_tools_copy b1)
status=$?
why=$(message "$status")
check "it fails"                          "1|" "$status|$row"
check "  with agent-vm's reason"          "1" "$(cad_has "$why" 'box b1 is not running')"
check "  and releases the lock"           "no" "$([ -d "$HOME/Library/Application Support/Cadabra/box-tools-b1.lock" ] && echo yes || echo no)"
fake_reset
/bin/mkdir -p "$HOME/Library/Application Support/Cadabra/box-tools-b1.lock"
row=$(CADABRA_BOXTOOLS_LOCK_WAIT=3 with_fake boxsession_tools_copy b1)
status=$?
why=$(message "$status")
check "another window's copy in progress refuses after the wait" "1" "$status"
check "  saying so"                       "1" "$(cad_has "$why" 'Another Cadabra window is still copying')"
check "  without running anything in the box" "0" "$(logged_count 'exec')"
/bin/rmdir "$HOME/Library/Application Support/Cadabra/box-tools-b1.lock"
check "a bad box name is refused"         "2" "$(with_fake boxsession_tools_copy 'B 1' >/dev/null; echo $?)"
# tar in the box takes an empty stream (a tar on this Mac that could not run) as an empty archive.
install_script=$(cad_lib_var _boxsession_tools_install "$LIB")
/bin/rm -rf "$OMCTEST_WORK/empty-copy"
/bin/sh -c "$install_script" sh "$OMCTEST_WORK/empty-copy/t1" "$OMCTEST_WORK/empty-copy/cache" Support/replay </dev/null 2>"$OMCTEST_WORK/empty-copy.err"
check "an empty stream fails the copy"    "1|no" "$?|$([ -f "$OMCTEST_WORK/empty-copy/t1/.cadabra-tools-complete" ] && echo yes || echo no)"
check "  naming what did not arrive"      "1" "$(cad_has "$(/bin/cat "$OMCTEST_WORK/empty-copy.err")" 'Support/replay did not arrive')"
/bin/rm -rf "$OMCTEST_WORK/empty-copy" "$OMCTEST_WORK/empty-copy.err"

section "a disposable box for the tools: the servers' hosts, the project, the copy, the record"
fake_reset
prefs_reset true
box=$(with_fake boxsession_start_tools w1 new:dev "$PROJECT" no)
status=$?
check "it starts"                         "0" "$status"
case "$box" in cadabra-tools-??????) named=yes ;; *) named="no: $box" ;; esac
check "  named cadabra-tools-<6 hex digits>" "yes" "$named"
check "  with Internet on, allowing any public host" \
    "box create $box --image dev --net allowlist --allow public --disposable --json" "$(logged 'box create')"
check "  the project shared by a warm-up" "exec --box $box --project $PROJECT -- /usr/bin/true" "$(logged 'exec --box '"$box"' --project')"
check "  registered for its window"       "w1${TAB}$box${TAB}yes${TAB}$PROJECT${TAB}no" "$(/usr/bin/cut -f1-5 "$REGISTRY")"
check "  the window's tools record"       "$box${TAB}$PROJECT${TAB}no${TAB}$TOOLS_ROOT/$TOOLS_ID${TAB}$PYCACHE" "$(cad_pb_get aichatv2_boxtools_w1)"
fake_reset
prefs_reset
box=$(with_fake boxsession_start_tools w1 new:dev "$PROJECT" no)
check "with Internet off (the default) it reaches no host" "0" "$(cad_has "$(logged 'box create')" '--allow')"
cad_call mcp_prefs_set_bool allow-network true
cad_call mcp_prefs_set_bool servers/search/enabled true
fake_reset
box=$(with_fake boxsession_start_tools w1 new:dev "$PROJECT" no)
check "  whatever this Mac's servers are set to" "0" "$(cad_has "$(logged 'box create')" '--allow')"

section "a kept box for the tools, read-only; the release clears the record"
fake_reset
prefs_reset
box=$(with_fake boxsession_start_tools w1 box:b1 "$PROJECT" yes)
check "it starts, under its own name"     "0|b1" "$?|$box"
check "  nothing is made"                 "" "$(logged 'box create')"
check "  the share is read-only"          "exec --box b1 --project $PROJECT --read-only -- /usr/bin/true" "$(logged 'exec --box b1 --project')"
check "  and so is the record"            "b1${TAB}$PROJECT${TAB}yes" "$(cad_pb_get aichatv2_boxtools_w1 | /usr/bin/cut -f1-3)"
check "  its rules are left alone with Internet off" "" "$(logged 'box network')"
with_fake boxsession_release w1
fake_reset
prefs_reset true
box=$(with_fake boxsession_start_tools w1 box:b1 "$PROJECT" no)
check "with Internet on a kept box gets the public rule added" "0|box network b1 --allow public --json" "$?|$(logged 'box network')"
with_fake boxsession_release w1
fake_reset
printf '%s' '[{"box": {"name": "b1", "network": {"mode": "open"}}, "state": "stopped"}]' > "$FAKE_AGENTVM_DIR/box-list.json"
box=$(with_fake boxsession_start_tools w1 box:b1 "$PROJECT" no)
check "  an open kept box reaches every host already: nothing added" "0|" "$?|$(logged 'box network')"
with_fake boxsession_release w1
fake_reset
printf '%s' '[{"box": {"name": "b1", "network": {"mode": "off"}}, "state": "stopped"}]' > "$FAKE_AGENTVM_DIR/box-list.json"
box=$(with_fake boxsession_start_tools w1 box:b1 "$PROJECT" no)
status=$?
why=$(message "$status")
check "  one whose network is off refuses Internet, before it starts" "1||" "$status|$(logged 'box start')|$(/bin/cat "$REGISTRY" 2>/dev/null)"
check "  saying why"                      "1" "$(cad_has "$why" 'has its network off, so Internet search & fetch cannot work in it')"
box_set internet false
box=$(with_fake boxsession_start_tools w1 box:b1 "$PROJECT" no)
check "  and starts with Internet off"    "0|b1" "$?|$box"
with_fake boxsession_release w1
check "the release clears the record"     "" "$(cad_pb_get aichatv2_boxtools_w1)"
check "  and the row"                     "" "$(/bin/cat "$REGISTRY")"
fake_reset
printf '%s' 'the project /x is inside your home folder' > "$FAKE_AGENTVM_DIR/fail-exec---box"
box=$(with_fake boxsession_start_tools w1 box:b1 "$PROJECT" no)
check "a refused share fails the start"   "1" "$?"
check "  with no record"                  "" "$(cad_pb_get aichatv2_boxtools_w1)"
check "  and a row left for the caller to release" "w1" "$(col 1 < "$REGISTRY")"
with_fake boxsession_release w1

section "the MCP config in box mode runs every server through agent-vm exec"
fake_reset
prefs_reset true
with_fake boxsession_start_tools w1 box:b1 "$PROJECT" no >/dev/null
cad_call mcp_prefs_set_string servers/local/project "/elsewhere/now"
json=$( ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib aichat.mcp.servers.library.sh \
    aichat_acp_transport_json /bin/mlx-agent openai http://127.0.0.1:8099/v1 w1 true 2>/dev/null ) )
cfg="$HOME/Library/Application Support/Cadabra/Sessions/w1/mcp-config.json"
guest="$TOOLS_ROOT/$TOOLS_ID"
check "the transport is mlx-agent with the config" "1" "$(cad_has "$json" '"--mcp-config"')"
check "  working in the box's project, not today's setting" "1" "$(cad_has "$json" "\"cwd\": \"$PROJECT\"")"
check "all four servers described themselves through the box" "local|pdf|time|search" \
    "$("$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -c 'import json, sys; print("|".join(s["name"] for s in json.load(open(sys.argv[1]))["servers"]))' "$cfg" 2>&1)"
check "each is agent-vm"                  "$FAKE|$FAKE|$FAKE|$FAKE" \
    "$(server "$cfg" local 's["command"]')|$(server "$cfg" pdf 's["command"]')|$(server "$cfg" time 's["command"]')|$(server "$cfg" search 's["command"]')"
check "replay: exec in the box's project, unconfined there by default, the project first" \
    "exec --box b1 --project $PROJECT -- $guest/Support/replay --mcp-server --no-sandbox --allow-write $PROJECT --allow-write /" \
    "$(server "$cfg" local '" ".join(s["args"])')"
check "  its tools gated as on this Mac"  "1" "$(server "$cfg" local '1 if "execute_command" in s.get("gatedTools", []) else 0')"
check "pdfutil: the project and the box's temporary folder, writable" \
    "exec --box b1 --project $PROJECT -- $guest/Support/pdfutil mcp --root $PROJECT --root /private/tmp --writable" \
    "$(server "$cfg" pdf '" ".join(s["args"])')"
check "the Python servers get their paths in the box through --env" \
    "exec --box b1 --project $PROJECT --env PYTHONPATH=$guest/Library/Packages --env PYTHONPYCACHEPREFIX=$PYCACHE -- $guest/Library/Python/bin/python3 -m duckduckgo_mcp_server.server" \
    "$(server "$cfg" search '" ".join(s["args"])')"
check "  and no environment on this Mac"  "none" "$(server "$cfg" search 's.get("env", "none")')"
check "no path of this Mac's sandbox reaches the box" "0" "$(cad_has "$(/bin/cat "$cfg")" '/opt/homebrew')"

section "box mode follows the box pane, not this Mac's servers"
fake_reset
prefs_reset
# This Mac's servers set otherwise, to show they do not count in a box.
cad_call mcp_prefs_set_bool allow-network false
cad_call mcp_prefs_set_bool servers/time/enabled false
with_fake boxsession_start_tools w1 box:b1 "$PROJECT" yes >/dev/null
( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib aichat.mcp.servers.library.sh \
    aichat_acp_transport_json /bin/mlx-agent openai http://127.0.0.1:8099/v1 w1 true >/dev/null 2>&1 )
check "Internet off: no search server; the time server needs no network" "absent|present" \
    "$(server "$cfg" search 's')|$(server "$cfg" time '"present"')"
check "  every exec is read-only; replay unconfined, with no network switch" \
    "exec --box b1 --project $PROJECT --read-only -- $guest/Support/replay --mcp-server --no-sandbox --allow-write $PROJECT --allow-write /" \
    "$(server "$cfg" local '" ".join(s["args"])')"
check "  pdfutil is not writable on a read-only project" "0" "$(server "$cfg" pdf '1 if "--writable" in s["args"] else 0')"
box_set confineLocal true
box_set time false
box_set pdf false
( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib aichat.mcp.servers.library.sh \
    aichat_acp_transport_json /bin/mlx-agent openai http://127.0.0.1:8099/v1 w1 true >/dev/null 2>&1 )
check "confined when asked: replay's box profile, the box's network" \
    "exec --box b1 --project $PROJECT --read-only -- $guest/Support/replay --mcp-server --allow-write $PROJECT --sandbox-profile $guest/Resources/replay-box-sandbox.json" \
    "$(server "$cfg" local '" ".join(s["args"])')"
check "  and it still describes itself through the box" "1" "$(server "$cfg" local '1 if "execute_command" in s.get("gatedTools", []) else 0')"
check "PDF and Date & Time off: not started" "absent|absent" "$(server "$cfg" pdf 's')|$(server "$cfg" time 's')"
box_set local false
box_set pdf true
( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib aichat.mcp.servers.library.sh \
    aichat_acp_transport_json /bin/mlx-agent openai http://127.0.0.1:8099/v1 w1 true >/dev/null 2>&1 )
check "Files and shell off: no Local server" "absent|present" "$(server "$cfg" local 's')|$(server "$cfg" pdf '"present"')"
prefs_reset
set_developer() {
    "$cad_plister" get type "$cad_settings" /developer >/dev/null 2>&1 || \
        "$cad_plister" insert developer dict "$cad_settings" / >/dev/null 2>&1
    "$cad_plister" get type "$cad_settings" "/developer/$1" >/dev/null 2>&1 || \
        "$cad_plister" insert "$1" string "" "$cad_settings" /developer >/dev/null 2>&1
    "$cad_plister" set string "$2" "$cad_settings" "/developer/$1" >/dev/null 2>&1
}
set_developer agent-vm-home "$OMCTEST_WORK/store"
( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib aichat.mcp.servers.library.sh \
    aichat_acp_transport_json /bin/mlx-agent openai http://127.0.0.1:8099/v1 w1 true >/dev/null 2>&1 )
check "another store reaches agent-vm through each server's env" "$OMCTEST_WORK/store" "$(server "$cfg" local 's["env"]["AGENT_VM_HOME"]')"
check "  and the probe ran agent-vm with it" "$OMCTEST_WORK/store" "$(/bin/cat "$FAKE_AGENTVM_DIR/home")"
set_developer agent-vm-home ""
with_fake boxsession_release w1
( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib aichat.mcp.servers.library.sh \
    aichat_acp_transport_json /bin/mlx-agent openai http://127.0.0.1:8099/v1 w1 true >/dev/null 2>&1 )
check "with the record cleared the servers run on this Mac again" "$OMC_APP_BUNDLE_PATH/Contents/Support/replay" "$(server "$cfg" local 's["command"]')"
cad_pb_set aichatv2_boxtools_w1 "b1${TAB}relative${TAB}no${TAB}/g${TAB}/c"
json=$( ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; cad_call_lib aichat.mcp.servers.library.sh \
    aichat_acp_transport_json /bin/mlx-agent openai http://127.0.0.1:8099/v1 w1 true 2>/dev/null ) )
check "an unusable record refuses the transport" "1|" "$?|$json"
cad_pb_set aichatv2_boxtools_w1 ""

section "chat init starts the tools' box before the engine"
fake_reset
prefs_reset
cad_pb_set aichatv2_open_w1 1
alerts_reset
out=$(engine chat_engine_tools_box w1 true)
check "tools on this Mac start nothing"   "0|0" "$(printf '%s\n' "$out" | /usr/bin/head -1)|$([ -f "$FAKE_AGENTVM_DIR/log" ] && echo 1 || echo 0)"
cad_call mcp_tools_set_run_in new:dev >/dev/null
out=$(engine chat_engine_tools_box w1 false)
check "  and nor do tools off, wherever they would run" "0|0" "$(printf '%s\n' "$out" | /usr/bin/head -1)|$([ -f "$FAKE_AGENTVM_DIR/log" ] && echo 1 || echo 0)"
out=$(engine chat_engine_tools_box w1 true)
box=$(col 2 < "$REGISTRY")
check "tools in a new box: it starts"     "0" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  the record names it"             "$box" "$(cad_pb_get aichatv2_boxtools_w1 | col 1)"
check "  the image is stamped for the conversation's record" "$box${TAB}dev" "$(cad_pb_get aichatv2_boximage_w1)"
check "  the box line shows, with no agent" "|$box" "$(cad_pb_get aichatv2_boxagent_w1)|$(cad_pb_get aichatv2_boxline_w1 | col 1)"
check "  no alert"                        "0" "$(alerts_count)"
with_fake boxsession_release w1

section "chat init refuses a tools box it cannot start, says why, and keeps nothing"
fake_reset
prefs_reset
cad_call mcp_tools_set_run_in new:dev >/dev/null
cad_call mcp_prefs_set_string servers/local/project ""
alerts_reset
out=$(engine chat_engine_tools_box w1 true)
check "no project folder refuses"         "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  saying where to choose one"      "1" "$(alerts_mention 'Choose the Project folder in Agentic Session Tools')"
check "  before agent-vm made anything"   "" "$(logged 'box create')"
cad_call mcp_prefs_set_string servers/local/project "$PROJECT"
"$cad_plister" set dict "$cad_settings" /servers/runIn >/dev/null 2>&1
alerts_reset
check "  (a place stored as something else reads as damaged)" "damaged" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_run_in)"
out=$(engine chat_engine_tools_box w1 true)
check "a place that cannot be read refuses" "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  rather than run the tools on this Mac" "1" "$(alerts_mention 'Where Cadabra')"
check "  choosing again repairs it"       "0|new:dev" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_set_run_in new:dev; echo $?)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_run_in)"
printf '0.1.0\n' > "$FAKE_AGENTVM_DIR/version"
alerts_reset
out=$(engine chat_engine_tools_box w1 true)
check "an agent-vm too old refuses"       "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  in the tools' words"             "1" "$(alerts_mention "Cadabra's tools are set to run in an AgentVM box")"
fake_reset
printf '%s' 'box create failed for a test' > "$FAKE_AGENTVM_DIR/fail-box-create"
alerts_reset
out=$(engine chat_engine_tools_box w1 true)
check "a box that cannot be made refuses" "1" "$(printf '%s\n' "$out" | /usr/bin/head -1)"
check "  with agent-vm's reason"          "1" "$(alerts_mention 'box create failed for a test')"
check "  and no row or record"            "|" "$(/bin/cat "$REGISTRY" 2>/dev/null)|$(cad_pb_get aichatv2_boxtools_w1)"
fake_reset
cad_pb_set aichatv2_open_w1 ""
alerts_reset
out=$(engine chat_engine_tools_box w1 true)
check "a window closed during the start refuses quietly" "1|0" "$(printf '%s\n' "$out" | /usr/bin/head -1)|$(alerts_count)"
check "  and its box is gone"             "0|" "$(/bin/ls "$FAKE_AGENTVM_DIR" | /usr/bin/grep -c '^box-cadabra-')|$(/bin/cat "$REGISTRY")"

section "a switch that turns tools on never moves them to this Mac"
# switch_tools <prev tools> <tools>  ->  chat_engine_switch's status for an MLX window whose tools
# were <prev tools>, switched to another MLX model with <tools>, then "|built" when a transport
# was asked for. The transport builder is stubbed: what matters is whether the switch got there.
MODELS="$OMCTEST_WORK/models"
for d in "$MODELS/Mlx-A" "$MODELS/Mlx-B"; do
    /bin/mkdir -p "$d"
    printf '{}' > "$d/config.json"
    /usr/bin/head -c 512 /dev/zero > "$d/model.safetensors"
done
MLX_A=$(cd "$MODELS/Mlx-A" && pwd -P)
switch_tools() {
    /bin/rm -f "$OMCTEST_WORK/switch-built"
    cad_pb_set aichatv2_modelpath_w2 "$MLX_A"
    cad_pb_set aichatv2_agent_w2 ""
    cad_pb_set aichatv2_port_w2 ""
    cad_pb_set aichatv2_tools_w2 "$1"
    cad_pb_set aichatv2_open_w2 1
    sw_status=$( ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM
        . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.chat.engine.library.sh" >/dev/null 2>&1
        aichat_acp_transport_json() { : > "$OMCTEST_WORK/switch-built"; printf '{"protocol":"acp"}\n'; }
        chat_engine_switch w2 "$MODELS/Mlx-B" "$2" >/dev/null 2>&1
        echo $? ) )
    printf '%s|%s\n' "$sw_status" "$([ -f "$OMCTEST_WORK/switch-built" ] && echo built)"
}
fake_reset
prefs_reset
cad_call mcp_tools_set_run_in new:dev >/dev/null
alerts_reset
check "tools off to on, set to run in a box, with no box: refused" "1|" "$(switch_tools false true)"
check "  saying why"                      "1" "$(alerts_mention 'this conversation started without tools, so it has no box')"
check "  the window keeps its model"      "$MLX_A|false" "$(cad_pb_get aichatv2_modelpath_w2)|$(cad_pb_get aichatv2_tools_w2)"
check "  and agent-vm never ran"          "0" "$(logged_count '')"
alerts_reset
check "tools already on (on this Mac): the switch goes on" "0|built" "$(switch_tools true true)"
check "tools off: the switch goes on"     "0|built" "$(switch_tools true false)"
cad_pb_set aichatv2_boxtools_w2 "b1${TAB}$PROJECT${TAB}no${TAB}/g${TAB}/c"
check "tools off to on with a box record: the switch goes on" "0|built" "$(switch_tools false true)"
check "  no alert"                        "0" "$(alerts_count)"
cad_pb_set aichatv2_boxtools_w2 ""
cad_call mcp_tools_set_run_in mac >/dev/null
check "tools off to on, set to run on this Mac: the switch goes on" "0|built" "$(switch_tools false true)"
cad_pb_set aichatv2_open_w2 ""

section "where the tools run and the share mode are stored as chosen"
cad_reset
check "the box pane's defaults" "true|false|true|true|true|false|false" \
    "$(for n in local confineLocal pdf pdfWritable time internet readOnly; do cad_call_lib aichat.mcp.servers.library.sh mcp_box_setting $n; done | /usr/bin/paste -sd'|' -)"
check "  a setting stores and reads back"  "0|true" "$(box_set confineLocal true; echo $?)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_box_setting confineLocal)"
check "  an unknown name or value is refused" "2|2" "$(box_set nosuch true; echo $?)|$(box_set internet maybe; echo $?)"
"$cad_plister" remove "$cad_settings" /servers/box/confineLocal >/dev/null 2>&1
"$cad_plister" insert confineLocal string true "$cad_settings" /servers/box >/dev/null 2>&1
check "  the text \"true\" reads as the default, as the generator reads it" "string|false" \
    "$("$cad_plister" get type "$cad_settings" /servers/box/confineLocal)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_box_setting confineLocal)"
check "  and choosing again replaces it"  "0|true" "$(box_set confineLocal true; echo $?)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_box_setting confineLocal)"
"$cad_plister" insert readOnly string yes "$cad_settings" /servers/box >/dev/null 2>&1
check "a share mode stored as something else is damaged, never read-write" "damaged" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_read_only)"
cad_reset
check "nothing stored reads as this Mac and read-write" "mac|no" \
    "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_run_in)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_read_only)"
check "a place that is not a choice is refused" "2" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_set_run_in 'somewhere'; echo $?)"
cad_call_lib aichat.mcp.servers.library.sh mcp_tools_set_run_in box:b1
box_set readOnly true
check "a kept box and read-only read back" "box:b1|yes" \
    "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_run_in)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_read_only)"

section "the box pane says what a kept box may reach"
net_places="${TMPDIR:-/tmp}/cadabra-runin-places.nettest$$"
printf 'available\nbox\tfenced\tallowlist\tpack:npm,opencode.ai\nbox\tbare\tallowlist\t-\nbox\tshut\toff\t-\nbox\twide\topen\t-\nbox\told\t-\t-\n' > "$net_places"
net_line() { cad_call_lib aichat.mcp.servers.library.sh mcp_tools_box_network_line "nettest$$" "box:$1"; }
check "an allowlist, its rules"           "Its network: allowlist - pack:npm, opencode.ai" "$(net_line fenced)"
check "  none"                            "Its network: allowlist, no rules" "$(net_line bare)"
check "  off"                             "Its network: off" "$(net_line shut)"
check "  open"                            "Its network: open (any host, also on your local network)" "$(net_line wide)"
check "  no mode recorded runs open in agent-vm, and says so" "Its network: open (any host, also on your local network)" "$(net_line old)"
/bin/rm -f "$net_places"

/bin/rm -rf "$TOOLS_ROOT" "$PYCACHE"
omctest_end
