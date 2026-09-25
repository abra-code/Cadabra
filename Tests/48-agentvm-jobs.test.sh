#!/bin/sh
# Tests/48-agentvm-jobs.test.sh - long agent-vm commands as detached jobs (agentvm_job.py).
#
# The real runner runs here, detached as in the app, around fake_agent_vm.sh, whose long
# commands print agent-vm's progress events a "delay" apart and stop on SIGINT or SIGTERM the
# way agent-vm does. What is pinned: a start returns at once while the job goes on; one job per
# target; progress, results and errors in the list; Cancel; a runner that dies leaves "lost";
# the orphan reaper leaves the runner alone; job ids cannot name a path.
#
# Needs the sandbox off (ps). POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.agentvm.library.sh
FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
export FAKE_AGENTVM_DIR
JOBS="$HOME/Library/Application Support/Cadabra/Jobs"
TAB=$(printf '\t')

unset CADABRA_AGENT_VM AGENT_VM_HOME

lib() { cad_call_lib "$LIB" "$@"; }
with_fake() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; lib "$@" )
}
message() { lib agentvm_last_error "$1"; }
col() { /usr/bin/cut -f"$1"; }

# fake_reset - a fake with two boxes, a free VM slot, and events <delay> seconds apart.
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
    /bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-b1.json"
    /bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-b2.json"
    /usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
    printf '%s\n' "$1" > "$FAKE_AGENTVM_DIR/delay"
}

# job_row <id>  ->  the job's row from agentvm_jobs.
job_row() { with_fake agentvm_jobs | /usr/bin/awk -F'\t' -v id="$1" '$1 == id'; }

# wait_until <id> <state> [tenths]  ->  the job's state once it is <state>, or its last state
# when that never came (default: 10 seconds).
wait_until() {
    w_left="${3:-100}"
    while :; do
        w_state=$(job_row "$1" | col 5)
        [ "$w_state" = "$2" ] && break
        [ "$w_left" -le 0 ] && break
        w_left=$((w_left - 1))
        /bin/sleep 0.1
    done
    printf '%s\n' "$w_state"
}

# swept <command line>  ->  yes or no, the orphan reaper's verdict.
swept() {
    cad_call_lib aichat.server.library.sh _bundle_managed_process "$1" && echo yes || echo no
}

/bin/rm -rf "$JOBS"

# -----------------------------------------------------------------------------------------
section "a box start runs detached, and its start call returns at once"
fake_reset 1
before=$(/bin/date +%s)
id=$(with_fake agentvm_box_start_job b1); rc=$?
after=$(/bin/date +%s)
check "started"                    "0" "$rc"
check "  an id, not a path"        "1" "$(printf '%s\n' "$id" | /usr/bin/grep -c '^[0123456789]\{8\}-[0123456789]\{6\}-[0123456789abcdef]\{6\}$')"
check "  returned before the job's two seconds of events" "1" "$([ $((after - before)) -le 1 ] && echo 1 || echo 0)"
row=$(job_row "$id")
check "  listed as running"        "running" "$(printf '%s\n' "$row" | col 5)"
check "  kind and target"          "box-start${TAB}box:b1" "$(printf '%s\n' "$row" | /usr/bin/cut -f2,3)"
check "  titled for people"        "Start b1" "$(printf '%s\n' "$row" | col 4)"
check "  no status yet"            "-" "$(printf '%s\n' "$row" | col 6)"
if [ -n "${OMC_APP_PROCESS_ID:-}" ]; then
    owner_args=" --owner-pid $OMC_APP_PROCESS_ID"
else
    owner_args=""
fi
/bin/sleep 0.3
check "  agent-vm got the box, the app as its owner, and --json" "box start b1$owner_args --json" "$(/usr/bin/grep '^box start' "$FAKE_AGENTVM_DIR/log")"

section "while it runs: progress from agent-vm's events"
check "the first event is there"   "starting${TAB}-${TAB}starting" "$(job_row "$id" | /usr/bin/cut -f9-11)"

section "one job per target"
out=$(with_fake agentvm_box_start_job b1); rc=$?
check "a second start of b1 is refused" "3" "$rc"
check "  naming the job in the way" "Start b1 is still running for b1. Wait for it to finish, or cancel it." "$(message "$rc")"
check "busy says which job"         "Start b1" "$(with_fake agentvm_job_busy box:b1)"
check "another box is not busy"     ""         "$(with_fake agentvm_job_busy box:b2)"

section "the orphan reaper leaves the runner alone"
runner=$(/bin/cat "$JOBS/$id/pid" 2>/dev/null)
args=$(/bin/ps -o args= -p "$runner" 2>/dev/null)
check "the runner's command line is the one the reaper knows" "1" "$(cad_has "$args" "agentvm_job.py run ")"
check "  and it is not swept"       "no" "$(swept "$args")"
check "  it is at PPID 1, as detached" "1" "$(/bin/ps -o ppid= -p "$runner" 2>/dev/null | /usr/bin/tr -d ' ')"
check "other bundled Python still is" "yes" "$(swept "$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3 $OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_job.py list /x")"

section "it ends done"
check "done"                        "done" "$(wait_until "$id" done)"
row=$(job_row "$id")
check "  status 0"                  "0"     "$(printf '%s\n' "$row" | col 6)"
check "  the last step"             "ready" "$(printf '%s\n' "$row" | col 9)"
check "  an end time"               "1" "$(printf '%s\n' "$row" | col 8 | /usr/bin/grep -c 'Z$')"
check "  no error"                  "-"     "$(printf '%s\n' "$row" | col 13)"
check "  agent-vm's answer was kept" "1" "$(/usr/bin/grep -c '"state"' "$JOBS/$id/out" | /usr/bin/tr -d ' ')"
check "b1 is free again"            ""      "$(with_fake agentvm_job_busy box:b1)"

section "Cancel"
fake_reset 3
id2=$(with_fake agentvm_box_stop_job b2)
/bin/sleep 0.5
with_fake agentvm_job_cancel "$id2"; rc=$?
check "asked to stop"               "0" "$rc"
check "ends canceled"               "canceled" "$(wait_until "$id2" canceled)"
check "  with agent-vm's 130"       "130" "$(job_row "$id2" | col 6)"
check "  and its message"           "stopping b2 was canceled" "$(with_fake agentvm_job_error "$id2")"
out=$(with_fake agentvm_job_cancel "$id2"); rc=$?
check "canceling a finished job is refused" "1" "$rc"
check "  saying so"                 "the job is not running" "$(message "$rc")"

section "a failure keeps agent-vm's message"
fake_reset 0
printf 'the guest daemon did not answer after the reboot; run `agent-vm image update-guest dev` again' > "$FAKE_AGENTVM_DIR/fail-image-update-guest"
id3=$(with_fake agentvm_image_update_guest_job dev)
check "ends failed"                 "failed" "$(wait_until "$id3" failed)"
row=$(job_row "$id3")
check "  status 1"                  "1" "$(printf '%s\n' "$row" | col 6)"
check "  its first line in the list" 'the guest daemon did not answer after the reboot; run `agent-vm image update-guest dev` again' "$(printf '%s\n' "$row" | col 13)"
check "  and all of it on request"  'the guest daemon did not answer after the reboot; run `agent-vm image update-guest dev` again' "$(with_fake agentvm_job_error "$id3")"
check "  titled for people"         "Update the guest in dev" "$(printf '%s\n' "$row" | col 4)"

section "forget"
with_fake agentvm_job_forget "$id3"; rc=$?
check "a finished job can be forgotten" "0" "$rc"
check "  and is gone from the list"  "" "$(job_row "$id3")"
check "  and from the disk"          "0" "$([ -e "$JOBS/$id3" ] && echo 1 || echo 0)"
fake_reset 3
id4=$(with_fake agentvm_image_setup_job dev)
out=$(with_fake agentvm_job_forget "$id4"); rc=$?
check "a running job cannot be"      "1" "$rc"
check "  saying why"                 "the job is still running; cancel it first" "$(message "$rc")"
with_fake agentvm_job_cancel "$id4" >/dev/null
wait_until "$id4" canceled >/dev/null

section "a runner that dies leaves the job lost, not running forever"
fake_reset 3
id5=$(with_fake agentvm_box_stop_job b1)
/bin/sleep 0.5
runner=$(/bin/cat "$JOBS/$id5/pid" 2>/dev/null)
args=$(/bin/ps -o args= -p "$runner" 2>/dev/null)
# Signaled by the pid the job recorded, after checking that pid is this job's runner.
case "$args" in
    *"agentvm_job.py run "*"$id5"*) /bin/kill -9 "$runner" ;;
esac
check "lost"                        "lost" "$(wait_until "$id5" lost 30)"
check "  saying what happened"      "The job ended without recording a result: its runner was stopped." "$(job_row "$id5" | col 13)"
check "  and b1 is not held by it"  "" "$(with_fake agentvm_job_busy box:b1)"
/bin/sleep 3

section "an unlimited descriptor limit does not lose the job"
# SC_OPEN_MAX is then LONG_MAX, which os.closerange refused: the runner died before it ran.
fake_reset 0
id7=$( ulimit -n unlimited 2>/dev/null; with_fake agentvm_box_stop_job b2 )
check "done, not lost"              "done" "$(wait_until "$id7" done)"

section "the store setting reaches the job's agent-vm"
fake_reset 0
cad_reset
[ -f "$cad_settings" ] || { /bin/mkdir -p "$(/usr/bin/dirname "$cad_settings")"; "$cad_plister" set dict "$cad_settings" / >/dev/null 2>&1; }
"$cad_plister" insert developer dict "$cad_settings" / >/dev/null 2>&1
"$cad_plister" insert agent-vm-home string "" "$cad_settings" /developer >/dev/null 2>&1
"$cad_plister" set string "/Volumes/Work/agent-vm" "$cad_settings" /developer/agent-vm-home >/dev/null 2>&1
id6=$(with_fake agentvm_box_stop_job b2)
wait_until "$id6" done >/dev/null
check "AGENT_VM_HOME, as agentvm_run sets it" "/Volumes/Work/agent-vm" "$(/bin/cat "$FAKE_AGENTVM_DIR/home")"
cad_reset

section "refused before any job exists"
fake_reset 0
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
count_before=$(/bin/ls "$JOBS" | /usr/bin/grep -c -- '-')
out=$(with_fake agentvm_box_start_job b1); rc=$?
check "no free VM slot: refused"    "1" "$rc"
check "  saying why"                "1" "$(cad_has "$(message "$rc")" "No virtual machine slot is free")"
check "  and no job was made"       "$count_before" "$(/bin/ls "$JOBS" | /usr/bin/grep -c -- '-')"
out=$(with_fake agentvm_box_stop_job "-b"); rc=$?
check "a name like an option"       "2" "$rc"
lib agentvm_last_error >/dev/null
out=$(with_fake agentvm_job_cancel "../../Jobs"); rc=$?
check "a job id that is a path"     "1" "$rc"
check "  is not a job id"           "1" "$(cad_has "$(message "$rc")" "is not a job id")"
out=$(with_fake agentvm_job_forget "20260101-000000-abcdef"); rc=$?
check "a job that does not exist"   "1" "$rc"
check "  says so"                   "there is no job 20260101-000000-abcdef" "$(message "$rc")"

section "no Python caches were written into the application"
check "no __pycache__ beside the scripts" "0" "$(/usr/bin/find "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts" -name __pycache__ | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end
