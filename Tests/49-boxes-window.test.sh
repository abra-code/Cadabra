#!/bin/sh
# Tests/49-boxes-window.test.sh - the AgentVM Boxes window (Tools > AgentVM Boxes): what it
# lists, what a selection enables, what Start, Stop, View and Open AgentVM ask for, how a job the
# window started is followed and its failure told once, and what the window says when boxes
# cannot be used.
#
# agent-vm is fake_agent_vm.sh (CADABRA_AGENT_VM). It answers `status` from a file a test
# leaves in its state folder (made from Tests/fixtures/agentvm/status-variety.json with jq), and
# a job it is asked to start never runs: a test moves it on by leaving a status that lists it.
# The poll loop is run by hand, one reading at a time (CADABRA_BOXES_POLL_PASSES), since omctest
# records chains without following them.
#
# This Mac must run the macOS boxes need: on an older one the window has nothing to show, and
# 45-agentvm-library.test.sh checks that gate.
#
# Needs the sandbox off. POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

cad_import_ids aichat.boxes.library.sh ""

FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
CADABRA_AGENT_VM="$FAKE"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
MIN_VERSION=$(/usr/bin/sed -n 's/^AGENTVM_MIN_VERSION="\(.*\)"$/\1/p' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh")
CADABRA_OPEN="$OMCTEST_WORK/fake_open.sh"
CADABRA_BOXES_POLL_BUSY=0
CADABRA_BOXES_POLL_IDLE=0
CADABRA_BOXES_POLL_PASSES=1
export CADABRA_AGENT_VM FAKE_AGENTVM_DIR CADABRA_OPEN CADABRA_BOXES_POLL_BUSY CADABRA_BOXES_POLL_IDLE CADABRA_BOXES_POLL_PASSES
unset AGENT_VM_HOME
TAB=$(printf '\t')
OPENED="$OMCTEST_WORK/opened"
RUN="$HOME/Library/Application Support/Cadabra/Run"

# The stand-in for /usr/bin/open: records its arguments, and fails while open-fails exists.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n[ -f "%s" ] && exit 1\nexit 0\n' "$OPENED" "$OMCTEST_WORK/open-fails" > "$CADABRA_OPEN"
/bin/chmod +x "$CADABRA_OPEN"

if [ -n "${OMC_APP_PROCESS_ID:-}" ]; then
    owner_args=" --owner-pid $OMC_APP_PROCESS_ID"
else
    owner_args=""
fi

# status_is <jq filter>  ->  what `agent-vm status` answers from now on: the variety fixture
# (cadabra-spike stopped and disposable, s3 running with two programs, try1 not answering; one
# of two virtual machines running; no jobs), changed by the filter.
status_is() {
    /usr/bin/jq "$1" "$FIXTURES/status-variety.json" > "$FAKE_AGENTVM_DIR/status.json"
}

# job <id> <state> <box> <start|stop> [status] [error]  ->  a jq filter that adds that job.
job() {
    printf '.jobs += [{"id": "%s", "state": "%s", "targets": ["box:%s"], "command": ["box", "%s", "%s", "--json"]%s%s}]' \
        "$1" "$2" "$3" "$4" "$3" "${5:+, \"status\": $5}" "${6:+, \"error\": \"$6\"}"
}

# fake_reset  ->  the fake with a free virtual machine slot and the variety status.
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
    /usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
    /bin/cp "$FIXTURES/box-status-running.json" "$FAKE_AGENTVM_DIR/box-s3.json"
    status_is .
    /bin/rm -f "$OPENED" "$OMCTEST_WORK/open-fails"
}
fake_log() { /bin/cat "$FAKE_AGENTVM_DIR/log" 2>/dev/null; }
fake_asked() { fake_log | /usr/bin/grep -c "^$1" | /usr/bin/tr -d ' '; }
last_job() { /usr/bin/tail -1 "$FAKE_AGENTVM_DIR/jobs" 2>/dev/null; }

# journal_count <uuid> <target> <verb>  ->  how many calls of that verb went to that target of
# that window (the harness journal: uuid, target, arguments).
journal_count() {
    /usr/bin/awk -F'\t' -v u="$1" -v t="$2" -v v="$3" '$1 == u && $2 == t && index($3, v) == 1 { n++ } END { print n + 0 }' "$OMCTEST_UI/journal.tsv"
}

# open_window  ->  a fresh AgentVM Boxes window, as the menu item opens it.
open_window() {
    ui_reset
    alerts_reset
    alert_answers_reset
    chains_reset
    omc_control_defaults aichat.boxes
    omc_run aichat.boxes.init
}

# select_box <name>  ->  a click on a box ("" for a click that deselects).
select_box() { omc_table_cell "$BOXES_LIST_ID" 1 "$1"; omc_run aichat.boxes.box.selection.changed; }
# poll  ->  one reading of the poll loop.
poll() { omc_run aichat.boxes.poll; }
card() { ui_rows "$BOXES_LIST_ID" | /usr/bin/awk -F'\t' -v name="$1" '$1 == name'; }
buttons() { printf '%s%s%s\n' "$(ui_enabled "$BOXES_START_ID")" "$(ui_enabled "$BOXES_STOP_ID")" "$(ui_enabled "$BOXES_VIEW_ID")"; }
watched() { cad_pb_get "cadabra_boxes_watch_$OMC_ACTIONUI_WINDOW_UUID" | /usr/bin/tr -d ' '; }

# -----------------------------------------------------------------------------------------
section "opening: the boxes and their states, nothing selected"
fake_reset
cad_reset
open_window
check_status "init ran"                 0
check "one status reading"              "1" "$(fake_asked "status --json")"
check "  and no list that would collect stopped disposable boxes" "0" "$(fake_asked "box list")"
check "the line counts the virtual machines" "Virtual machines running on this Mac: 1 of 2" "$(ui_value "$BOXES_STATUS_ID")"
check "three boxes"                     "3" "$(ui_row_count "$BOXES_LIST_ID")"
check "  a stopped disposable one"      "cadabra-spike${TAB}stop.circle${TAB}Stopped - dev-agents, 4 GB, disposable${TAB}#8E8E93" "$(card cadabra-spike)"
check "  a running one, with its programs" "s3${TAB}play.circle.fill${TAB}Running, 2 programs - dev-acp, 8 GB${TAB}#2E9E4F" "$(card s3)"
check "  one that does not answer"      "try1${TAB}exclamationmark.circle.fill${TAB}Not responding - dev, 8 GB${TAB}#E8861A" "$(card try1)"
check "Start, Stop and View are off"    "000" "$(buttons)"
check "Open AgentVM is on"              "1" "$(ui_enabled "$BOXES_APP_ID")"
check "the poll loop is asked for"      "1" "$(chain_asked aichat.boxes.poll)"
check "the window is known to the menu item" "$OMC_ACTIONUI_WINDOW_UUID" "$(cad_pb_get "cadabra_boxes_window_$OMC_APP_PROCESS_ID")"

section "a selection enables what the box's state allows"
select_box s3
check "running: Stop and View"          "011" "$(buttons)"
select_box cadabra-spike
check "stopped: Start"                  "100" "$(buttons)"
select_box try1
check "not answering: Stop only"        "010" "$(buttons)"
select_box ""
check "nothing selected: none"          "000" "$(buttons)"
select_box "no such box"
check "a name that is not a box name selects nothing" "000|" "$(buttons)|$(cad_pb_get "cadabra_boxes_selected_$OMC_ACTIONUI_WINDOW_UUID")"

section "a reading that changed nothing sets the list once"
fake_reset
open_window
poll
poll
check "three readings"                  "3" "$(fake_asked "status --json")"
check "  one list"                      "1" "$(journal_count "$OMC_ACTIONUI_WINDOW_UUID" "$BOXES_LIST_ID" omc_table_set_rows_from_stdin)"
status_is '.boxes[0].state = "running"'
poll
check "a changed state sets it again"   "2" "$(journal_count "$OMC_ACTIONUI_WINDOW_UUID" "$BOXES_LIST_ID" omc_table_set_rows_from_stdin)"
check "  with the new state"            "Running - dev-agents, 4 GB, disposable" "$(card cadabra-spike | /usr/bin/cut -f3)"

# -----------------------------------------------------------------------------------------
section "Start: a job, followed until the box runs"
fake_reset
open_window
select_box cadabra-spike
chains_reset
omc_run aichat.boxes.box.start
check "asked as an agent-vm job, owned by Cadabra" "job start --json -- box start cadabra-spike$owner_args" "$(fake_log | /usr/bin/grep '^job start')"
JOB=$(last_job | /usr/bin/cut -f1)
check "the window watches the job"      "$JOB" "$(watched)"
check "no alert"                        "0" "$(alerts_count)"
status_is "$(job "$JOB" running cadabra-spike start)"
poll
check "while it runs the box is Starting" "cadabra-spike${TAB}circle.dotted${TAB}Starting - dev-agents, 4 GB, disposable${TAB}#0A84FF" "$(card cadabra-spike)"
check "  and takes no button"           "000" "$(buttons)"
check "  still watched"                 "$JOB" "$(watched)"
status_is "$(job "$JOB" done cadabra-spike start 0) | .boxes[0].state = \"running\" | .boxes[0].activeExecs = 0"
poll
check "done: the box runs"              "Running - dev-agents, 4 GB, disposable" "$(card cadabra-spike | /usr/bin/cut -f3)"
check "  Stop and View are on"          "011" "$(buttons)"
check "  the job is forgotten"          "" "$(watched)"
check "  and nothing was alerted"       "0" "$(alerts_count)"

section "a job that waits behind another"
fake_reset
open_window
status_is "$(job 20261002-101500-aaaaaa queued cadabra-spike start)"
poll
check "the box is Waiting"              "Waiting - dev-agents, 4 GB, disposable" "$(card cadabra-spike | /usr/bin/cut -f3)"
status_is "$(job 20261002-101500-aaaaaa queued cadabra-spike start) | $(job 20261002-101500-bbbbbb running cadabra-spike stop)"
poll
check "a job that runs wins over one that waits" "Stopping - dev-agents, 4 GB, disposable" "$(card cadabra-spike | /usr/bin/cut -f3)"

section "a start that fails in the background is told once"
fake_reset
open_window
select_box cadabra-spike
omc_run aichat.boxes.box.start
JOB=$(last_job | /usr/bin/cut -f1)
status_is "$(job "$JOB" failed cadabra-spike start 75 'no slot; see agent-vm box list')"
poll
check "an alert names the box"          "1" "$(alerts_mention 'Could not start cadabra-spike')"
check "  with Cadabra's words for a full set of slots" "1" "$(alerts_mention 'macOS runs at most two macOS virtual machines at once')"
check "  not agent-vm's, which name a Terminal command" "0" "$(alerts_mention 'agent-vm box list')"
check "  and the job is forgotten"      "" "$(watched)"
poll
check "the next reading does not tell it again" "1" "$(alerts_count)"
check "the box can be started again"    "100" "$(buttons)"
fake_reset
open_window
select_box s3
alert_answer 0
omc_run aichat.boxes.box.stop
JOB=$(last_job | /usr/bin/cut -f1)
alerts_reset
status_is "$(job "$JOB" failed s3 stop 1 'the guest did not shut down')"
poll
check "a stop that fails: agent-vm's own reason" "1|1" "$(alerts_mention 'Could not stop s3')|$(alerts_mention 'the guest did not shut down')"
fake_reset
open_window
status_is "$(job 20261002-101500-cccccc failed cadabra-spike start 1 'somebody else started this')"
poll
check "a failed job this window did not start is not its to tell" "0" "$(alerts_count)"
fake_reset
open_window
select_box cadabra-spike
omc_run aichat.boxes.box.start
JOB=$(last_job | /usr/bin/cut -f1)
status_is "$(job "$JOB" canceled cadabra-spike start 130 'canceled')"
poll
check "a canceled job is forgotten without an alert" "0|" "$(alerts_count)|$(watched)"

section "a job started while a reading is under way stays watched"
# The poll loop and a handler overlap. A reading takes the watch list before it asks agent-vm, so
# a job that Start adds after that is not judged by an answer that is older than the job.
note_jobs() { cad_call_lib aichat.boxes.library.sh boxes_note_jobs "$OMC_ACTIONUI_WINDOW_UUID" "$1"; }
fake_reset
open_window
select_box cadabra-spike
omc_run aichat.boxes.box.start
JOB=$(last_job | /usr/bin/cut -f1)
note_jobs ""
check "a reading that began before the start leaves it watched" "$JOB" "$(watched)"
cad_pb_set "cadabra_boxes_watch_$OMC_ACTIONUI_WINDOW_UUID" " 20261002-101500-dddddd $JOB"
note_jobs "20261002-101500-dddddd"
check "  also when it forgets a job that is long gone" "$JOB" "$(watched)"
printf 'the store is locked by another agent-vm' > "$FAKE_AGENTVM_DIR/fail-status---json"
poll
check "a reading that fails forgets nothing" "$JOB|0" "$(watched)|$(alerts_count)"
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-status---json"
status_is "$(job "$JOB" failed cadabra-spike start 1 'the disk is full')"
poll
check "  and the failure is told by the next one that works" "1|" "$(alerts_mention 'the disk is full')|$(watched)"
note_jobs "$JOB"
check "a failure another reading took off the list is not told again" "1" "$(alerts_count)"

section "a start that cannot begin says so at once"
fake_reset
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
open_window
select_box cadabra-spike
omc_run aichat.boxes.box.start
check "no free slot: an alert"          "1" "$(alerts_mention 'Could not start cadabra-spike')"
check "  and no job"                    "0" "$(fake_asked "job start")"
fake_reset
printf 'a job for box:cadabra-spike already runs' > "$FAKE_AGENTVM_DIR/fail-job-start"
open_window
select_box cadabra-spike
omc_run aichat.boxes.box.start
check "agent-vm's refusal of the job, in its words" "1" "$(alerts_mention 'a job for box:cadabra-spike already runs')"
check "  and nothing is watched"        "" "$(watched)"

# -----------------------------------------------------------------------------------------
section "Stop: asked about when programs run in the box"
fake_reset
open_window
select_box s3
alert_answer 1
omc_run aichat.boxes.box.stop
check "it asks, naming how many"        "1" "$(alerts_mention 'Programs running in the box right now: 2')"
check "  Cancel stops nothing"          "0" "$(fake_asked "job start")"
alerts_reset
alert_answers_reset
alert_answer 0
omc_run aichat.boxes.box.stop
check "Stop: a job"                     "job start --json -- box stop s3" "$(fake_log | /usr/bin/grep '^job start')"
check "  watched"                       "$(last_job | /usr/bin/cut -f1)" "$(watched)"
fake_reset
status_is '.boxes[1].activeExecs = 0'
open_window
select_box s3
omc_run aichat.boxes.box.stop
check "no programs: no question"        "0|1" "$(alerts_count)|$(fake_asked "job start --json -- box stop s3")"

section "View"
fake_reset
open_window
select_box s3
omc_run aichat.boxes.box.view
check "the box's screen, without control" "box view s3 --json" "$(fake_log | /usr/bin/tail -1)"
printf 'the box s3 is not running' > "$FAKE_AGENTVM_DIR/fail-box-view"
omc_run aichat.boxes.box.view
check "agent-vm's refusal is alerted"   "1|1" "$(alerts_mention 'Could not show s3')|$(alerts_mention 'the box s3 is not running')"

section "Open AgentVM"
fake_reset
open_window
omc_run aichat.boxes.agentvm.open
check "nothing selected: the app"       "agentvm://status" "$(/bin/cat "$OPENED")"
/bin/rm -f "$OPENED"
select_box s3
omc_run aichat.boxes.agentvm.open
check "a box selected: the app at that box" "agentvm://box/s3" "$(/bin/cat "$OPENED")"
check "  and no alert"                  "0" "$(alerts_count)"
/bin/rm -f "$OPENED"
: > "$OMCTEST_WORK/open-fails"
alert_answer 0
omc_run aichat.boxes.agentvm.open
check "no app on this Mac: an alert"    "1" "$(alerts_mention 'The AgentVM app is not on this Mac')"
check "  whose button opens the download page" "https://github.com/abra-code/AgentVMApp/releases" "$(/usr/bin/tail -1 "$OPENED")"
/bin/rm -f "$OMCTEST_WORK/open-fails"

# -----------------------------------------------------------------------------------------
section "no boxes yet"
fake_reset
status_is '.boxes = [] | .runningVMs.count = 0'
open_window
check "the line says where to make one" "No boxes yet. Open AgentVM to make one." "$(ui_value "$BOXES_STATUS_ID")"
check "  and the list is empty"         "0" "$(ui_row_count "$BOXES_LIST_ID")"

section "a selected box that is gone"
fake_reset
open_window
select_box cadabra-spike
status_is 'del(.boxes[0])'
poll
check "two boxes"                       "2" "$(ui_row_count "$BOXES_LIST_ID")"
check "  nothing is selected"           "" "$(cad_pb_get "cadabra_boxes_selected_$OMC_ACTIONUI_WINDOW_UUID")"
check "  and no button applies"         "000" "$(buttons)"

section "boxes cannot be used: one line, the reason in its tooltip, and the way out"
fake_reset
printf '0.1.11\n' > "$FAKE_AGENTVM_DIR/version"
open_window
check "a test double that is too old: its own reason" "1" "$(cad_has "$(ui_value "$BOXES_STATUS_ID")" "Cadabra needs agent-vm $MIN_VERSION or later")"
check "  nothing is listed"             "0|0" "$(ui_row_count "$BOXES_LIST_ID")|$(fake_asked "status")"
check "  no button applies"             "000" "$(buttons)"
check "  Open AgentVM stays on"         "1" "$(ui_enabled "$BOXES_APP_ID")"
# No seam and no setting: the installed agent-vm, which the scratch home does not have.
fake_reset
# Not in a subshell: a check made in one is not counted.
unset CADABRA_AGENT_VM
open_window
check "nothing installed: what to do, in one line" "AgentVM is not set up on this Mac. Open AgentVM to set it up." "$(ui_value "$BOXES_STATUS_ID")"
check "  the whole reason is the tooltip" "1" "$(cad_has "$(ui_prop "$BOXES_STATUS_ID" help)" "there is no agent-vm at $HOME/.local/bin/agent-vm")"
check "  Open AgentVM is on"            "1" "$(ui_enabled "$BOXES_APP_ID")"
/bin/mkdir -p "$HOME/.local/bin"
/bin/ln -s "$FAKE" "$HOME/.local/bin/agent-vm"
printf '0.1.11\n' > "$FAKE_AGENTVM_DIR/version"
omc_run aichat.boxes.refresh
check "an installed one that is too old" "AgentVM on this Mac needs an update. Open AgentVM to update it." "$(ui_value "$BOXES_STATUS_ID")"
/bin/rm -f "$FAKE_AGENTVM_DIR/version"
omc_run aichat.boxes.refresh
check "updated meanwhile: Refresh finds the boxes" "3" "$(ui_row_count "$BOXES_LIST_ID")"
check "  and the tooltip is gone"       "" "$(ui_prop "$BOXES_STATUS_ID" help)"
CADABRA_AGENT_VM="$FAKE"
export CADABRA_AGENT_VM
/bin/rm -rf "$HOME/.local"
fake_reset
open_window
printf 'the store is locked by another agent-vm' > "$FAKE_AGENTVM_DIR/fail-status---json"
omc_run aichat.boxes.refresh
check "a status that fails: the line says so" "The boxes could not be read." "$(ui_value "$BOXES_STATUS_ID")"
check "  agent-vm's reason is the tooltip" "1" "$(cad_has "$(ui_prop "$BOXES_STATUS_ID" help)" "the store is locked by another agent-vm")"
check "  and the boxes last read stay"  "3" "$(ui_row_count "$BOXES_LIST_ID")"

# -----------------------------------------------------------------------------------------
section "the poll loop: one per window, none after it closes"
fake_reset
open_window
check "after a reading the loop gives its place up" "" "$(poll; cad_pb_get "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID")"
cad_pb_set "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID" "poll-$$"
chains_reset
omc_run aichat.boxes.activated
check "activation reads at once"        "1" "$([ "$(fake_asked "status --json")" -ge 3 ] && echo 1 || echo 0)"
check "  and starts no second loop"     "0" "$(chain_asked aichat.boxes.poll)"
cad_pb_set "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID" ""
chains_reset
omc_run aichat.boxes.activated
check "  one when none runs"            "1" "$(chain_asked aichat.boxes.poll)"
# A pid nothing has: the largest macOS gives out is 99998.
cad_pb_set "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID" "poll-99999999"
chains_reset
omc_run aichat.boxes.activated
check "  and one when the loop that held the place is gone" "1" "$(chain_asked aichat.boxes.poll)"
omc_run aichat.boxes.close
check "closing marks the window closed" "closed" "$(cad_pb_get "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID")"
check "  forgets it"                    "" "$(cad_pb_get "cadabra_boxes_window_$OMC_APP_PROCESS_ID")"
check "  and removes its files"         "0" "$(/bin/ls "$RUN" 2>/dev/null | /usr/bin/grep -c "^boxes\.$OMC_ACTIONUI_WINDOW_UUID\." | /usr/bin/tr -d ' ')"
asked_before=$(fake_asked "status --json")
poll
check "a loop chained before the close reads nothing" "$asked_before" "$(fake_asked "status --json")"

section "Tools > AgentVM Boxes: one window, brought to the front"
fake_reset
ui_reset
omc_window_switch boxes3
omc_control_defaults aichat.boxes
omc_run aichat.boxes.init
boxes3="$OMC_ACTIONUI_WINDOW_UUID"
chains_reset
omc_run aichat.boxes.open
check "an open window comes to the front" "1" "$(journal_count "$boxes3" omc_window omc_select)"
check "  and no second one opens"       "0" "$(chain_asked aichat.boxes)"
omc_run aichat.boxes.close
chains_reset
omc_run aichat.boxes.open
check "none open: one opens"            "1" "$(chain_asked aichat.boxes)"
check "  and the closed one is not asked to come forward" "1" "$(journal_count "$boxes3" omc_window omc_select)"
cad_pb_set "cadabra_boxes_window_999999" "$boxes3"
chains_reset
omc_run aichat.boxes.open
check "a uuid another Cadabra process left behind is not read" "1" "$(chain_asked aichat.boxes)"
cad_pb_set "cadabra_boxes_window_999999" ""

section "a handler run by a link, with no window, does nothing"
fake_reset
ui_reset
alerts_reset
saved_uuid="$OMC_ACTIONUI_WINDOW_UUID"
OMC_ACTIONUI_WINDOW_UUID=""
ACTIONUI_WINDOW_UUID=""
export OMC_ACTIONUI_WINDOW_UUID ACTIONUI_WINDOW_UUID
omc_table_cell "$BOXES_LIST_ID" 1 s3
for handler in box.start box.stop box.view agentvm.open refresh box.selection.changed init activated poll close; do
    omc_run "aichat.boxes.$handler"
done
check "agent-vm was not run"            "" "$(fake_log)"
check "  nothing was opened"            "" "$(/bin/cat "$OPENED" 2>/dev/null)"
check "  and nothing was alerted"       "0" "$(alerts_count)"
OMC_ACTIONUI_WINDOW_UUID="$saved_uuid"
ACTIONUI_WINDOW_UUID="$saved_uuid"
export OMC_ACTIONUI_WINDOW_UUID ACTIONUI_WINDOW_UUID

section "a conversation set to run in a box, where boxes cannot be used"
# chat_engine_agentvm_ready is what a chat start asks first. A missing or old agent-vm is the
# AgentVM app's to fix, so the alert's button opens the app; nothing is installed from here.
ready() { cad_call_lib aichat.chat.engine.library.sh chat_engine_agentvm_ready "This agent is" >/dev/null; }
fake_reset
alerts_reset
alert_answers_reset
ready
check "a usable agent-vm: ready, no alert" "0|0" "$?|$(alerts_count)"
unset CADABRA_AGENT_VM
alert_answer 0
ready
check "nothing installed: not ready"   "1" "$?"
check "  the alert says what is set and why it cannot be" "1|1" "$(alerts_mention 'This agent is set to run in an AgentVM box, and boxes cannot be used yet')|$(alerts_mention 'AgentVM is not set up on this Mac')"
check "  Open AgentVM opens the app"   "agentvm://status" "$(/bin/cat "$OPENED" 2>/dev/null)"
/bin/rm -f "$OPENED"
alerts_reset
alert_answers_reset
alert_answer 1
ready
check "  Cancel opens nothing"         "1|" "$?|$(/bin/cat "$OPENED" 2>/dev/null)"
CADABRA_AGENT_VM="$FAKE"
export CADABRA_AGENT_VM
printf '0.1.11\n' > "$FAKE_AGENTVM_DIR/version"
alerts_reset
alert_answers_reset
alert_answer 0
ready
check "a test double that is too old: an alert with no app to open" "1|1|" "$?|$(alerts_mention 'boxes cannot be used here')|$(/bin/cat "$OPENED" 2>/dev/null)"
fake_reset

section "every view id constant is defined once"
# A later definition silently wins in sh, so a reused name retargets every earlier use.
check "no constant is defined twice" "" "$(/usr/bin/sed -n 's/^\(BOXES_[A-Z_]*_ID\)=.*/\1/p' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh" | /usr/bin/sort | /usr/bin/uniq -d)"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no table was clobbered by a value" "" "$(ui_suspect_writes)"

omctest_end
