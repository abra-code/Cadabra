#!/bin/sh
# Tests/47-agentvm-boxes.test.sh - what Cadabra reads from agent-vm about boxes (images, boxes,
# the exec and network logs, the status the AgentVM Boxes window polls), the commands it runs
# itself (create, delete, view, the free-slot check, a start or a stop as an agent-vm job, a shell
# in Terminal), and the links that open the AgentVM app.
#
# agent-vm never runs here: CADABRA_AGENT_VM points the library at fake_agent_vm.sh, which
# answers from JSON captured from a real agent-vm (Tests/fixtures/agentvm/).
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.agentvm.library.sh
FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
CONVERT="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_json.py"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
export FAKE_AGENTVM_DIR
TAB=$(printf '\t')

unset CADABRA_AGENT_VM AGENT_VM_HOME CADABRA_OPEN

lib() { cad_call_lib "$LIB" "$@"; }
with_fake() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; lib "$@" )
}
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
}
convert() { "$PY" "$CONVERT" "$1" < "$2"; }
col() { /usr/bin/cut -f"$1"; }
count_rows() { /usr/bin/awk 'END { print NR }'; }
# absent <names...>  ->  the names of the columns of stdin's first row that are "-".
absent() {
    /usr/bin/awk -F'\t' -v names="$*" 'NR == 1 { n = split(names, name, " "); for (i = 1; i <= n; i++) if (name[i] != "_" && $i == "-") printf "%s ", name[i] }'
}
last_call() { /usr/bin/tail -1 "$FAKE_AGENTVM_DIR/log"; }
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
message() { lib agentvm_last_error "$1"; }

# -----------------------------------------------------------------------------------------
section "images: one row per image"
rows=$(convert images "$FIXTURES/image-list.json")
check "one row per image"  "5" "$(printf '%s\n' "$rows" | count_rows)"
row=$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$1 == "dev-agents"')
check "fifteen fields"     "15"             "$(printf '%s\n' "$row" | /usr/bin/awk -F'\t' '{ print NF }')"
check "state"              "ready"          "$(printf '%s\n' "$row" | col 2)"
check "no failure is \"-\"" "-"             "$(printf '%s\n' "$row" | col 3)"
check "macOS with its build" "27.0 (26A428)" "$(printf '%s\n' "$row" | col 4)"
check "based on"           "dev-node"       "$(printf '%s\n' "$row" | col 5)"
check "own size, in decimal units" "220 MB" "$(printf '%s\n' "$row" | col 6)"
check "needs, for people"  "guest update"   "$(printf '%s\n' "$row" | col 7)"
check "created, the day"   "2026-09-23"     "$(printf '%s\n' "$row" | col 9)"
check "memory in GB"       "8"              "$(printf '%s\n' "$row" | col 12)"
check "needs, for code"    "guest-update"   "$(printf '%s\n' "$row" | col 15)"
check "a base image has no \"based on\"" "-" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$1 == "dev" { print $5 }')"

section "drift: every image field the library reads is in the fixture"
check "no field is absent" "" "$(printf '%s\n' "$row" | absent name state _ macOS basedOn ownSize needs recipe created guestVersion cpus memoryGB diskGB path needKinds)"

section "boxes: one row per box"
rows=$(convert boxes "$FIXTURES/box-list.json")
row=$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$1 == "cadabra-spike"')
check "eighteen fields"    "18"             "$(printf '%s\n' "$row" | /usr/bin/awk -F'\t' '{ print NF }')"
check "state"              "stopped"        "$(printf '%s\n' "$row" | col 2)"
check "image"              "dev-agents"     "$(printf '%s\n' "$row" | col 3)"
check "network, for people" "allowlist, 1 rule" "$(printf '%s\n' "$row" | col 4)"
check "memory in GB"       "4"              "$(printf '%s\n' "$row" | col 6)"
check "own size"           "545 MB"         "$(printf '%s\n' "$row" | col 7)"
check "a stopped box has no pid" "-"        "$(printf '%s\n' "$row" | col 8)"
check "the network mode, for code" "allowlist" "$(printf '%s\n' "$row" | col 17)"
check "the rules"          "pack:npm"       "$(printf '%s\n' "$row" | col 18)"
check "drift: no stored field is absent" "" "$(printf '%s\n' "$row" | absent name state image network cpus memoryGB ownSize _ _ _ _ _ _ _ _ path netMode rules)"

section "boxes: a running disposable box, from the fields box status has"
printf '%s' '[{"box":{"name":"cadabra-x","image":"dev","cpuCount":2,"memoryBytes":4294967296,"network":{"mode":"allowlist","allow":["pack:npm","example.com"]}},"state":"running","running":true,"pid":812,"project":"/p","projectReadOnly":false,"activeExecs":2,"disposable":true,"ownerPid":77,"startedAt":"2026-09-25T09:18:17Z","supervisorVersion":"0.2.1","path":"/b","diskUsage":{"bytes":9000000000}}]' > "$OMCTEST_WORK/running.json"
row=$(convert boxes "$OMCTEST_WORK/running.json")
check "two rules"          "allowlist, 2 rules" "$(printf '%s\n' "$row" | col 4)"
check "the supervisor pid" "812"            "$(printf '%s\n' "$row" | col 8)"
check "read-write is \"false\", not absent" "false" "$(printf '%s\n' "$row" | col 10)"
check "programs running"   "2"              "$(printf '%s\n' "$row" | col 11)"
check "disposable"         "true"           "$(printf '%s\n' "$row" | col 12)"
check "its owner"          "77"             "$(printf '%s\n' "$row" | col 13)"
check "without unsharedBytes, the whole size" "9.0 GB" "$(printf '%s\n' "$row" | col 7)"
check "rules, comma-joined" "pack:npm,example.com" "$(printf '%s\n' "$row" | col 18)"
printf '%s' '[{"box":{"name":"o","network":{"mode":"off"}},"state":"stopped"}]' > "$OMCTEST_WORK/off.json"
check "network off is just \"off\"" "off" "$(convert boxes "$OMCTEST_WORK/off.json" | col 4)"

section "the two logs"
row=$(convert execlog "$FIXTURES/execlog.json" | /usr/bin/head -1)
check "execlog: six fields" "6"              "$(printf '%s\n' "$row" | /usr/bin/awk -F'\t' '{ print NF }')"
check "  started"           "2026-09-25T07:36:52Z" "$(printf '%s\n' "$row" | col 1)"
check "  the exit status"   "0"              "$(printf '%s\n' "$row" | col 2)"
check "  the program, space-joined" "/bin/echo ok" "$(printf '%s\n' "$row" | col 4)"
check "  no prompts"        "-"              "$(printf '%s\n' "$row" | col 5)"
check "  not stopped on one" "false"         "$(printf '%s\n' "$row" | col 6)"
printf '%s' '[{"argv":["/usr/bin/find","/Users/agent/Downloads"],"started":"t","prompts":["the Downloads folder","Photos"],"stoppedOnPrompt":true,"status":143,"seconds":4.5},{"argv":["/bin/sleep","60"],"started":"t2"}]' > "$OMCTEST_WORK/prompts.json"
rows=$(convert execlog "$OMCTEST_WORK/prompts.json")
check "a run that waited on prompts names them" "the Downloads folder; Photos" "$(printf '%s\n' "$rows" | /usr/bin/head -1 | col 5)"
check "  and says it was stopped"   "true"  "$(printf '%s\n' "$rows" | /usr/bin/head -1 | col 6)"
check "  a fractional duration"     "4.5"   "$(printf '%s\n' "$rows" | /usr/bin/head -1 | col 3)"
check "a run with no end is \"no end recorded\"" "no end recorded" "$(printf '%s\n' "$rows" | /usr/bin/tail -1 | col 2)"
row=$(convert netlog "$FIXTURES/netlog.json" | /usr/bin/head -1)
check "netlog: time, decision, host, port, method, reason" "2026-09-25T07:37:04Z${TAB}denied${TAB}bag.itunes.apple.com${TAB}443${TAB}CONNECT${TAB}not in the allowlist" "$row"

section "the conversions refuse the wrong shape"
out=$(convert images "$FIXTURES/doctor.json" 2>/dev/null); rc=$?
check "an object where a list belongs" "1" "$rc"
check "  prints no row"                ""  "$out"

# -----------------------------------------------------------------------------------------
section "the list functions ask agent-vm exactly this"
fake_reset
check "images"   "5" "$(with_fake agentvm_images | count_rows)"
check "  asked"  "image list --json" "$(last_call)"
with_fake agentvm_boxes >/dev/null
check "boxes asked"  "box list --json" "$(last_call)"
/bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-b1.json"
with_fake agentvm_execlog b1 >/dev/null
check "execlog asked" "box execlog b1 --json" "$(last_call)"
with_fake agentvm_execlog b1 20 >/dev/null
check "  with a count" "box execlog b1 --last 20 --json" "$(last_call)"
with_fake agentvm_netlog b1 50 denied >/dev/null
check "netlog with a count, refusals only" "box netlog b1 --last 50 --denied --json" "$(last_call)"
with_fake agentvm_netlog b1 "" denied >/dev/null
check "  refusals only"  "box netlog b1 --denied --json" "$(last_call)"
with_fake agentvm_netlog b1 >/dev/null
check "  everything"     "box netlog b1 --json" "$(last_call)"

section "log arguments that could be read as options never reach agent-vm"
fake_reset
out=$(with_fake agentvm_execlog b1 -5); rc=$?
check "a negative count is refused" "2" "$rc"
check "  saying why"                "1" "$(cad_has "$(message "$rc")" "must be a whole number")"
out=$(with_fake agentvm_netlog --all); rc=$?
check "a box name like an option"   "2" "$rc"
check "  saying why"                "1" "$(cad_has "$(message "$rc")" "is not a box name agent-vm accepts")"
check "  and agent-vm never ran"    "0" "$([ -s "$FAKE_AGENTVM_DIR/log" ] && echo 1 || echo 0)"

# -----------------------------------------------------------------------------------------
section "box create: the argv, rule by rule"
fake_reset
with_fake agentvm_box_create cadabra-y dev "" "" allowlist yes; rc=$?
check "succeeds"                    "0" "$rc"
check "  defaults: no --cpus or --memory-gb, and no rules" "box create cadabra-y --image dev --net allowlist --disposable --json" "$(last_call)"
check "  the box now exists (the fake made its record)" "1" "$([ -f "$FAKE_AGENTVM_DIR/box-cadabra-y.json" ] && echo 1 || echo 0)"
with_fake agentvm_box_create b2 dev-node 2 6 allowlist no pack:npm "*.example.com" api.example.com:8443; rc=$?
check "with everything"             "0" "$rc"
check "  one --allow per rule, in order" "box create b2 --image dev-node --net allowlist --allow pack:npm --allow *.example.com --allow api.example.com:8443 --cpus 2 --memory-gb 6 --json" "$(last_call)"
with_fake agentvm_box_create b3 dev "" "" off no
check "network off"                 "box create b3 --image dev --net off --json" "$(last_call)"
out=$(with_fake agentvm_box_create b2 dev "" "" open no); rc=$?
check "an existing name fails with agent-vm's message" "1" "$rc"
check "  which reaches the alert"   "a box named b2 already exists" "$(message "$rc")"

section "box create refuses before agent-vm runs"
fake_reset
refused() {
    with_fake agentvm_box_create "$@" >/dev/null
    printf '%s|%s' "$?" "$([ -s "$FAKE_AGENTVM_DIR/log" ] && echo ran || echo quiet)"
}
check "a bad box name"      "2|quiet" "$(refused Box1 dev "" "" allowlist no)"
check "a bad image name"    "2|quiet" "$(refused b1 -dev "" "" allowlist no)"
check "an unknown network"  "2|quiet" "$(refused b1 dev "" "" wide no)"
check "a rule like an option" "2|quiet" "$(refused b1 dev "" "" allowlist no pack:npm --net=open)"
check "  its reason"        "1" "$(cad_has "$(message 2)" "\"--net=open\" is not a network rule")"
check "an empty rule"       "2|quiet" "$(refused b1 dev "" "" allowlist no "")"
check "a rule with a space" "2|quiet" "$(refused b1 dev "" "" allowlist no "a b")"
check "zero CPUs"           "2|quiet" "$(refused b1 dev 0 "" allowlist no)"
check "memory not a number" "2|quiet" "$(refused b1 dev "" 4GB allowlist no)"
check "disposable not yes or no" "2|quiet" "$(refused b1 dev "" "" allowlist maybe)"
lib agentvm_last_error >/dev/null

section "delete and view"
fake_reset
/bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-b1.json"
with_fake agentvm_box_delete b1; rc=$?
check "deleting a box"          "0" "$rc"
check "  asked"                 "box delete b1 --json" "$(last_call)"
out=$(with_fake agentvm_box_delete b1); rc=$?
check "deleting it again fails" "1" "$rc"
check "  with agent-vm's words" 'no box b1; `agent-vm box list` shows the existing ones' "$(message "$rc")"
/bin/cp "$FIXTURES/box-status-running.json" "$FAKE_AGENTVM_DIR/box-b2.json"
with_fake agentvm_box_view b2
check "view"                    "box view b2 --json" "$(last_call)"
with_fake agentvm_box_view b2 interactive
check "  interactive"           "box view b2 --interactive --json" "$(last_call)"

# -----------------------------------------------------------------------------------------
section "a free virtual machine slot"
fake_reset
out=$(with_fake agentvm_vm_slot_free); rc=$?
check "the fixture's two running VMs: none free" "1" "$rc"
why=$(message "$rc")
check "  doctor's own count is in the reason" "1" "$(cad_has "$why" "No virtual machine slot is free: 2 virtual machines running on this Mac")"
check "  and where to stop a box"   "1" "$(cad_has "$why" "Stop a box in Tools > AgentVM Boxes, or a virtual machine in another application, then try again.")"
printf '%s' '[{"box":{"name":"s3","network":{"mode":"off"}},"state":"running"},{"box":{"name":"try1","network":{"mode":"off"}},"state":"stopped"},{"box":{"name":"b2","network":{"mode":"off"}},"state":"starting"},{"box":{"name":"b4","network":{"mode":"off"}},"state":"stopping"}]' > "$FAKE_AGENTVM_DIR/box-list.json"
with_fake agentvm_vm_slot_free; rc=$?
check "running boxes: refused"      "1" "$rc"
check "  naming those that run or start" "1" "$(cad_has "$(message "$rc")" "AgentVM boxes running: s3, b2. Stop one in Tools > AgentVM")"
/bin/rm -f "$FAKE_AGENTVM_DIR/box-list.json"
/usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
with_fake agentvm_vm_slot_free; rc=$?
check "an ok count: free"       "0" "$rc"
/usr/bin/sed 's/"warning"/"info"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
with_fake agentvm_vm_slot_free; rc=$?
check "could not count: not a reason to refuse" "0" "$rc"
printf '1\n' > "$FAKE_AGENTVM_DIR/exit"
with_fake agentvm_vm_slot_free; rc=$?
check "doctor failing: let agent-vm decide" "0" "$rc"
check "  and no stale message is left" "agent-vm failed (status 0) and gave no reason." "$(message 0)"

# -----------------------------------------------------------------------------------------
section "a shell in Terminal"
fake_reset
/bin/cp "$FIXTURES/box-status-running.json" "$FAKE_AGENTVM_DIR/box-b1.json"
cad_reset
opened="$OMCTEST_WORK/opened"
/bin/cat > "$OMCTEST_WORK/fake_open.sh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$opened"
EOF
/bin/chmod +x "$OMCTEST_WORK/fake_open.sh"
/bin/rm -f "$opened"
( CADABRA_AGENT_VM="$FAKE"; CADABRA_OPEN="$OMCTEST_WORK/fake_open.sh"; export CADABRA_AGENT_VM CADABRA_OPEN; lib agentvm_box_shell b1 ); rc=$?
file="$HOME/Library/Application Support/Cadabra/Shells/b1.command"
check "succeeds"                   "0" "$rc"
check "  Terminal opens the file"  "-a Terminal $file" "$(/bin/cat "$opened" 2>/dev/null)"
check "  which only its owner can run" "-rwx------" "$(/bin/ls -l "$file" | /usr/bin/cut -c1-10)"
check "  and runs the shell"       "exec '$FAKE' box shell b1" "$(/usr/bin/tail -1 "$file")"
check "  with no store setting, no AGENT_VM_HOME" "0" "$(/usr/bin/grep -c AGENT_VM_HOME "$file" | /usr/bin/tr -d ' ')"
check "  and it is valid sh"       "0" "$(/bin/sh -n "$file"; echo $?)"
# A store path with a quote and a space must survive as one word.
set_developer agent-vm-home "/Volumes/Tom's Disk/agent-vm"
( CADABRA_AGENT_VM="$FAKE"; CADABRA_OPEN="$OMCTEST_WORK/fake_open.sh"; export CADABRA_AGENT_VM CADABRA_OPEN; lib agentvm_box_shell b1 )
got=$(FAKE_AGENTVM_DIR="$FAKE_AGENTVM_DIR" /bin/sh -c ". '$file'" 2>/dev/null)
check "a store with a quote reaches agent-vm intact" "/Volumes/Tom's Disk/agent-vm" "$(/bin/cat "$FAKE_AGENTVM_DIR/home")"
check "  and the shell ran"        "fake shell in b1" "$got"
out=$( ( CADABRA_AGENT_VM="$FAKE"; CADABRA_OPEN="$OMCTEST_WORK/fake_open.sh"; export CADABRA_AGENT_VM CADABRA_OPEN; lib agentvm_box_shell "../x" ) ); rc=$?
check "a name with a slash is refused" "2" "$rc"
check "  and no file is written outside Shells" "0" "$([ -e "$HOME/Library/Application Support/Cadabra/x.command" ] && echo 1 || echo 0)"
lib agentvm_last_error >/dev/null
cad_reset

section "status: the boxes, the jobs and the virtual machines of one answer"
# status_rows <function> <file>  ->  one of the library's jq filters over a status answer.
status_rows() { lib "$1" < "$2"; }
rows=$(status_rows agentvm_status_box_rows "$FIXTURES/status-variety.json")
check "one row per box"            "3" "$(printf '%s\n' "$rows" | count_rows)"
check "a stopped disposable box"   "cadabra-spike${TAB}stopped${TAB}dev-agents${TAB}4${TAB}-${TAB}-${TAB}true${TAB}-" "$(printf '%s\n' "$rows" | /usr/bin/sed -n 1p)"
check "a running one: its programs and its owner" "s3${TAB}running${TAB}dev-acp${TAB}8${TAB}2${TAB}812${TAB}false${TAB}-" "$(printf '%s\n' "$rows" | /usr/bin/sed -n 2p)"
check "one that does not answer says why" "no answer from the supervisor within 5 s" "$(printf '%s\n' "$rows" | /usr/bin/sed -n 3p | col 8)"
check "every row has eight fields" "8 8 8" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '{ printf "%s%s", sep, NF; sep = " " }')"
check "the virtual machines"       "1${TAB}2" "$(status_rows agentvm_status_vm_row "$FIXTURES/status-variety.json")"
check "no jobs: no rows"           "" "$(status_rows agentvm_status_job_rows "$FIXTURES/status-variety.json")"
rows=$(status_rows agentvm_status_job_rows "$FIXTURES/status.json")
check "drift: a real capture's jobs have an id, a state, a target and a command" "" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '{ for (i = 1; i <= 4; i++) if ($i == "-") printf "row %d field %d ", NR, i }')"
check "  the box job among them"   "done${TAB}box:cadabra-spike${TAB}box stop${TAB}0${TAB}-" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$3 == "box:cadabra-spike"' | /usr/bin/cut -f2-)"
/usr/bin/jq '.jobs = [{"id": "20261002-101500-a1b2c3", "state": "failed", "status": 75, "targets": ["box:s3"], "command": ["box", "start", "s3", "--json"], "error": "no free slot\tfor s3\nstop one"}]' "$FIXTURES/status-variety.json" > "$OMCTEST_WORK/failed.json"
check "a failed job: its status, and its error on one line" "20261002-101500-a1b2c3${TAB}failed${TAB}box:s3${TAB}box start${TAB}75${TAB}no free slot for s3 stop one" "$(status_rows agentvm_status_job_rows "$OMCTEST_WORK/failed.json")"
fake_reset
with_fake agentvm_status >/dev/null
check "status asked"               "status --json" "$(last_call)"

section "starting and stopping a box as agent-vm jobs"
fake_reset
/usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
if [ -n "${OMC_APP_PROCESS_ID:-}" ]; then
    owner_args=" --owner-pid $OMC_APP_PROCESS_ID"
else
    owner_args=""
fi
id=$(with_fake agentvm_box_start_job b1); rc=$?
check "a start"                    "0" "$rc"
check "  answers with the job's id" "20261002-101500-000001" "$id"
check "  asked as a job, owned by Cadabra" "job start --json -- box start b1$owner_args" "$(last_call)"
id=$(with_fake agentvm_box_stop_job b1); rc=$?
check "a stop"                     "0|20261002-101500-000002" "$rc|$id"
check "  asked as a job"           "job start --json -- box stop b1" "$(last_call)"
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
starts_before=$(/usr/bin/grep -c 'box start b1' "$FAKE_AGENTVM_DIR/log")
id=$(with_fake agentvm_box_start_job b1); rc=$?
check "no free slot: no start"     "1|" "$rc|$id"
check "  and no job was asked for" "$starts_before" "$(/usr/bin/grep -c 'box start b1' "$FAKE_AGENTVM_DIR/log")"
lib agentvm_last_error >/dev/null
id=$(with_fake agentvm_box_stop_job b1); rc=$?
check "  a stop needs no slot"     "0" "$rc"
id=$(with_fake agentvm_box_start_job "-x"); rc=$?
check "a name that could be an option is refused" "2|" "$rc|$id"
lib agentvm_last_error >/dev/null
printf 'a job for box:b1 already runs' > "$FAKE_AGENTVM_DIR/fail-job-start"
id=$(with_fake agentvm_box_stop_job b1); rc=$?
check "agent-vm's refusal of a job" "1|" "$rc|$id"
check "  in its words"             "a job for box:b1 already runs" "$(message "$rc")"
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-job-start"
printf 'not-an-id' > "$FAKE_AGENTVM_DIR/job-id"
id=$(with_fake agentvm_box_stop_job b1); rc=$?
check "an answer without a job id is a failure" "1|" "$rc|$id"
check "  that says so"             "agent-vm started a job and did not say which." "$(message "$rc")"
for id in 20261001-094934-a1b2c3 2; do
    lib agentvm_valid_job_id "$id"
    check "job id $id" "0" "$?"
done
for id in "" "-20261001" "2026 1" "2026;x" "20261001-094934-A1B2C3" "20261001-094934-a1b2c3-20261001-094934-a1b2c3"; do
    lib agentvm_valid_job_id "$id"
    check "not a job id: \"$id\"" "1" "$?"
done

section "the AgentVM app, opened by its links"
fake_reset
cad_reset
opened="$OMCTEST_WORK/opened"
# The stand-in for /usr/bin/open: records its arguments, and fails while open-fails exists.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n[ -f "%s" ] && exit 1\nexit 0\n' "$opened" "$OMCTEST_WORK/open-fails" > "$OMCTEST_WORK/fake_open.sh"
/bin/chmod +x "$OMCTEST_WORK/fake_open.sh"
with_open() {
    ( CADABRA_AGENT_VM="$FAKE"; CADABRA_OPEN="$OMCTEST_WORK/fake_open.sh"; export CADABRA_AGENT_VM CADABRA_OPEN; lib "$@" )
}
/bin/rm -f "$opened" "$OMCTEST_WORK/open-fails"
with_open agentvm_app_open; rc=$?
check "the app"                    "0|agentvm://status" "$rc|$(/bin/cat "$opened")"
/bin/rm -f "$opened"
with_open agentvm_app_open s3; rc=$?
check "at a box"                   "0|agentvm://box/s3" "$rc|$(/bin/cat "$opened")"
/bin/rm -f "$opened"
with_open agentvm_app_open "s3/../x"; rc=$?
check "a name that is not a box name opens nothing" "2|" "$rc|$(/bin/cat "$opened" 2>/dev/null)"
lib agentvm_last_error >/dev/null
: > "$OMCTEST_WORK/open-fails"
with_open agentvm_app_open; rc=$?
check "no app answers the link"    "1" "$rc"
check "  and the reason says where to get it" "The AgentVM app is not on this Mac. Get it from https://github.com/abra-code/AgentVMApp/releases." "$(message "$rc")"
alerts_reset
alert_answers_reset
alert_answer 0
/bin/rm -f "$opened"
with_open agentvm_app_show s3; rc=$?
check "shown from a button: an alert says the app is missing" "1|1" "$rc|$(alerts_mention 'The AgentVM app is not on this Mac')"
check "  and its button opens the download page" "https://github.com/abra-code/AgentVMApp/releases" "$(/usr/bin/tail -1 "$opened")"
alerts_reset
alert_answers_reset
alert_answer 1
/bin/rm -f "$opened"
with_open agentvm_app_show; rc=$?
check "  Cancel opens nothing more" "1" "$(/usr/bin/awk 'END { print NR }' "$opened")"
/bin/rm -f "$OMCTEST_WORK/open-fails"
alerts_reset
alert_answers_reset
with_open agentvm_app_show; rc=$?
check "an app that opens: no alert" "0|0" "$rc|$(alerts_count)"
cad_reset

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end
