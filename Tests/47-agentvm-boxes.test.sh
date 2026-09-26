#!/bin/sh
# Tests/47-agentvm-boxes.test.sh - what the Box Manager reads from agent-vm (images, boxes,
# packs, the exec and network logs), and the quick commands it runs itself (create, delete,
# view, the free-slot check, a shell in Terminal).
#
# agent-vm never runs here: CADABRA_AGENT_VM points the library at fake_agent_vm.sh, which
# answers from JSON captured from a real agent-vm (Tests/fixtures/agentvm/). The long commands,
# run as detached jobs, are 48-agentvm-jobs.test.sh.
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
section "images: one row per image, the fields the Box Manager shows"
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
printf '%s' '[{"box":{"name":"cadabra-x","image":"dev","cpuCount":2,"memoryBytes":4294967296,"network":{"mode":"allowlist","allow":["pack:npm","example.com"]}},"state":"ready","running":true,"pid":812,"project":"/p","projectReadOnly":false,"activeExecs":2,"disposable":true,"ownerPid":77,"startedAt":"2026-09-25T09:18:17Z","supervisorVersion":"0.2.1","path":"/b","diskUsage":{"bytes":9000000000}}]' > "$OMCTEST_WORK/running.json"
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

section "packs, and the two logs"
rows=$(convert packs "$FIXTURES/packs.json")
check "npm is a pack" "1" "$(printf '%s\n' "$rows" | /usr/bin/grep -c "^npm${TAB}")"
check "hosts, comma-joined" "1" "$(cad_has "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$1 == "github" { print $2 }')" "github.com,api.github.com")"
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
with_fake agentvm_packs >/dev/null
check "packs asked"  "box packs --json" "$(last_call)"
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
printf 'image dev is in use by the box b1; delete the box first' > "$FAKE_AGENTVM_DIR/fail-image-delete"
out=$(with_fake agentvm_image_delete dev); rc=$?
check "an image in use is refused by agent-vm" "1" "$rc"
check "  naming the box"        "image dev is in use by the box b1; delete the box first" "$(message "$rc")"
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-image-delete"
with_fake agentvm_image_delete dev; rc=$?
check "deleting an image"       "0" "$rc"
check "  asked"                 "image delete dev --json" "$(last_call)"
/bin/cp "$FIXTURES/box-status-ready.json" "$FAKE_AGENTVM_DIR/box-b2.json"
with_fake agentvm_box_view b2
check "view"                    "box view b2 --json" "$(last_call)"
with_fake agentvm_box_view b2 interactive
check "  interactive"           "box view b2 --interactive --json" "$(last_call)"

# -----------------------------------------------------------------------------------------
section "a free virtual machine slot"
fake_reset
out=$(with_fake agentvm_vm_slot_free); rc=$?
check "the fixture's two running VMs: none free" "1" "$rc"
check "  doctor's own count is in the reason" "1" "$(cad_has "$(message "$rc")" "No virtual machine slot is free: 2 virtual machines running on this Mac")"
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
/bin/cp "$FIXTURES/box-status-ready.json" "$FAKE_AGENTVM_DIR/box-b1.json"
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

section "the recipes Cadabra ships"
RECIPES="$OMC_APP_BUNDLE_PATH/Contents/Resources/Recipes"
rows=$(lib agentvm_recipes)
check "four, by folder name" "acp-agents homebrew-node xcode xcode-platforms" "$(printf '%s\n' "$rows" | col 1 | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "  each with its recipe.json" "$RECIPES/xcode/recipe.json" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$1 == "xcode" { print $2 }')"
check "  and its description" "Homebrew and Node" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$1 == "homebrew-node" { print $3 }')"
check "homebrew-node's copied file came along" "1" "$([ -f "$RECIPES/homebrew-node/files/zprofile" ] && echo 1 || echo 0)"

section "a recipe's inputs and parameters"
rows=$(lib agentvm_recipe_info "$RECIPES/xcode/recipe.json")
check "the recipe row: kind, -, -, commandLineTools" "recipe${TAB}-${TAB}-${TAB}true" "$(printf '%s\n' "$rows" | /usr/bin/head -1 | /usr/bin/cut -f1-4)"
check "one input, always required" "input${TAB}xcode${TAB}true${TAB}-" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$1 == "input"' | /usr/bin/cut -f1-4)"
rows=$(lib agentvm_recipe_info "$RECIPES/acp-agents/recipe.json")
check "parameters with defaults are not required" "parameter${TAB}claude_acp${TAB}false${TAB}0.81.2" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$2 == "claude_acp"' | /usr/bin/cut -f1-4)"
check "an empty default is \"-\"" "-" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$2 == "extras" { print $4 }')"
printf '%s' '{"version":1,"description":"a\tb","parameters":{"need":{"description":"no default"}},"steps":[]}' > "$OMCTEST_WORK/r.json"
rows=$(lib agentvm_recipe_info "$OMCTEST_WORK/r.json")
check "a parameter without a default is required" "true" "$(printf '%s\n' "$rows" | /usr/bin/awk -F'\t' '$2 == "need" { print $3 }')"
check "  and a tab in a description stays in its field" "a?b" "$(printf '%s\n' "$rows" | /usr/bin/head -1 | col 5)"
out=$(lib agentvm_recipe_info recipe.json); rc=$?
check "a relative path is refused" "2" "$rc"
lib agentvm_last_error >/dev/null
printf 'not json' > "$OMCTEST_WORK/bad.json"
out=$(lib agentvm_recipe_info "$OMCTEST_WORK/bad.json"); rc=$?
check "a file that is not a recipe fails" "1" "$rc"
check "  saying so" "1" "$(cad_has "$(message "$rc")" "agentvm_json.py recipe")"

section "building an image: the argv"
fake_reset
/usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
printf 'xip' > "$OMCTEST_WORK/Xcode.xip"
printf 'ipsw' > "$OMCTEST_WORK/Restore.ipsw"
# wait_log <pattern> - until the detached job's agent-vm call is in the fake's log (5 s at most).
wait_log() {
    w_left=50
    while [ "$w_left" -gt 0 ]; do
        /usr/bin/grep -q "$1" "$FAKE_AGENTVM_DIR/log" 2>/dev/null && return 0
        w_left=$((w_left - 1))
        /bin/sleep 0.1
    done
}
id=$(with_fake agentvm_image_create_job dev-xc from dev "$RECIPES/xcode/recipe.json" 2 "" 128 "input:xcode=$OMCTEST_WORK/Xcode.xip" "set:mode=a=b c"); rc=$?
check "from an image, with a recipe: started" "0" "$rc"
wait_log "^image create dev-xc"
check "  the argv, every option in place" "image create dev-xc --from dev --input xcode=$OMCTEST_WORK/Xcode.xip --set mode=a=b c --recipe $RECIPES/xcode/recipe.json --cpus 2 --disk-gb 128 --json" "$(/usr/bin/grep '^image create dev-xc' "$FAKE_AGENTVM_DIR/log")"
id=$(with_fake agentvm_image_create_job base ipsw "" "" "" "" "" 2>/dev/null); rc=$?
check "from a restore image with no path: refused" "2" "$rc"
lib agentvm_last_error >/dev/null
id=$(with_fake agentvm_image_create_job base ipsw "$OMCTEST_WORK/Restore.ipsw" "" "" "" ""); rc=$?
check "from a restore image: started" "0" "$rc"
wait_log "^image create base"
check "  the argv" "image create base --ipsw $OMCTEST_WORK/Restore.ipsw --json" "$(/usr/bin/grep '^image create base' "$FAKE_AGENTVM_DIR/log")"

section "building an image: what is refused before agent-vm runs"
fake_reset
/usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
refused_build() {
    with_fake agentvm_image_create_job "$@" >/dev/null
    rb_rc=$?
    rb_msg=$(message "$rb_rc")
    printf '%s|%s' "$rb_rc" "$(/bin/cat "$FAKE_AGENTVM_DIR/log" 2>/dev/null | /usr/bin/grep -c '^image create' | /usr/bin/tr -d ' ')"
}
check "a relative restore image"       "2|0" "$(refused_build x ipsw Restore.ipsw "" "" "" "")"
check "a file that is not an .ipsw"    "2|0" "$(refused_build x ipsw "$OMCTEST_WORK/Xcode.xip" "" "" "" "")"
check "a restore image that is missing" "2|0" "$(refused_build x ipsw /nowhere/R.ipsw "" "" "" "")"
check "a base image name like an option" "2|0" "$(refused_build x from -dev "" "" "" "")"
check "a relative recipe"              "2|0" "$(refused_build x from dev recipe.json "" "" "")"
check "a parameter name in capitals"   "2|0" "$(refused_build x from dev "$RECIPES/acp-agents/recipe.json" "" "" "" "set:Extras=x")"
check "an input with a relative file"  "2|0" "$(refused_build x from dev "$RECIPES/xcode/recipe.json" "" "" "" "input:xcode=Xcode.xip")"
check "an input with a missing file"   "2|0" "$(refused_build x from dev "$RECIPES/xcode/recipe.json" "" "" "" "input:xcode=/nowhere.xip")"
check "an extra that is neither"       "2|0" "$(refused_build x from dev "" "" "" "" "xcode=/a")"
check "a disk size that is not a number" "2|0" "$(refused_build x from dev "" "" "" 1TB)"
check "too few arguments"              "2|0" "$(refused_build x from dev)"
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
check "no free VM slot"                "1|0" "$(refused_build x from dev "" "" "" "")"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end
