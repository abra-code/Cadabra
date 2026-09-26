#!/bin/sh
# Tests/49-boxes-window.test.sh - the Box Manager window (Tools > Boxes...) and the New Box
# window: what they list, what a selection shows and enables, and what each button asks
# agent-vm to do.
#
# agent-vm is fake_agent_vm.sh (CADABRA_AGENT_VM), answering from Tests/fixtures/agentvm/. Jobs
# are real detached runners around the fake, as in 48-agentvm-jobs.test.sh; the poll loop is
# run by hand where a test needs it, since omctest records chains without following them.
#
# Needs the sandbox off (the job runner). POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

cad_import_ids aichat.boxes.library.sh ""

FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
CADABRA_AGENT_VM="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
CADABRA_OPEN="$OMCTEST_WORK/fake_open.sh"
export CADABRA_AGENT_VM FAKE_AGENTVM_DIR CADABRA_OPEN
unset AGENT_VM_HOME
JOBS="$HOME/Library/Application Support/Cadabra/Jobs"
TAB=$(printf '\t')

/bin/cat > "$CADABRA_OPEN" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$OMCTEST_WORK/opened"
EOF
/bin/chmod +x "$CADABRA_OPEN"

# fake_reset [delay] - the fake with the fixture boxes' records and a free VM slot.
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
    /bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-cadabra-spike.json"
    /bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-try1.json"
    /usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
    printf '%s\n' "${1:-0}" > "$FAKE_AGENTVM_DIR/delay"
}
fake_log() { /bin/cat "$FAKE_AGENTVM_DIR/log" 2>/dev/null; }
fake_asked() { fake_log | /usr/bin/grep -c "^$1" | /usr/bin/tr -d ' '; }

# journal_count <uuid> <target> <verb>  ->  how many calls of that verb went to that target of
# that window (the harness journal: uuid, target, arguments).
journal_count() {
    /usr/bin/awk -F'\t' -v u="$1" -v t="$2" -v v="$3" '$1 == u && $2 == t && index($3, v) == 1 { n++ } END { print n + 0 }' "$OMCTEST_UI/journal.tsv"
}

# open_window - a fresh Box Manager, as the menu item opens it.
open_window() {
    ui_reset
    omc_control_defaults aichat.boxes
    omc_run aichat.boxes.init
}

# select_image <name> / select_box <name> / select_job <id> - a click on a row.
select_image() { omc_table_cell "$BOXES_IMAGES_ID" 1 "$1"; omc_run aichat.boxes.image.selection.changed; }
select_box()   { omc_table_cell "$BOXES_BOXES_ID" 1 "$1";  omc_run aichat.boxes.box.selection.changed; }
select_job()   { omc_table_cell "$BOXES_JOBS_ID" 4 "$1";  omc_run aichat.boxes.job.selection.changed; }

# wait_jobs_done - until no job runs (10 seconds at most).
wait_jobs_done() {
    w_left=100
    while [ "$w_left" -gt 0 ]; do
        w_running=$(/usr/bin/find "$JOBS" -name lock 2>/dev/null | while read -r w_lock; do
            [ -f "$(/usr/bin/dirname "$w_lock")/exit" ] || echo x; done | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        [ "$w_running" = "0" ] && return 0
        w_left=$((w_left - 1))
        /bin/sleep 0.1
    done
}

/bin/rm -rf "$JOBS"

# -----------------------------------------------------------------------------------------
section "opening: the header, the images, the boxes, no jobs"
fake_reset
cad_reset
open_window
check_status "init ran"                      0
check "the header names agent-vm and where it comes from" "agent-vm 0.1.8 (test double)" "$(ui_value "$BOXES_HEADER_ID")"
check "five images"                          "5" "$(ui_row_count "$BOXES_IMAGES_ID")"
check "  a row: name, state, macOS, base, own size, needs" "dev-agents${TAB}ready${TAB}27.0 (26A428)${TAB}dev-node${TAB}220 MB${TAB}guest update" "$(ui_rows "$BOXES_IMAGES_ID" | /usr/bin/grep '^dev-agents')"
check "two boxes"                            "2" "$(ui_row_count "$BOXES_BOXES_ID")"
check "  a row: name, state, image, network, CPUs, memory, own size" "cadabra-spike${TAB}stopped${TAB}dev-agents${TAB}allowlist, 1 rule${TAB}4${TAB}4 GB${TAB}545 MB" "$(ui_rows "$BOXES_BOXES_ID" | /usr/bin/grep '^cadabra-spike')"
check "no jobs"                              "0" "$(ui_row_count "$BOXES_JOBS_ID")"
check "the images are shown"                 "1" "$(ui_visible "$BOXES_IMAGES_ID")"
check "  and the boxes hidden"               "0" "$(ui_visible "$BOXES_BOXES_ID")"
check "no progress bar"                      "0" "$(ui_visible "$BOXES_PROGRESS_ID")"
check "no poll loop without jobs"            "0" "$(chain_asked aichat.boxes.poll)"
check "the manager is known to other windows" "$OMC_ACTIONUI_WINDOW_UUID" "$(cad_pb_get "cadabra_boxes_manager_window_$OMC_APP_PROCESS_ID")"
check "doctor's warnings are shown (none: the slot fixture is ok)" "" "$(ui_value "$BOXES_NOTES_ID")"

section "doctor's warnings reach the notes line"
fake_reset
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
open_window
check "the full VM slots"    "1" "$(cad_has "$(ui_value "$BOXES_NOTES_ID")" "running VMs: 2 virtual machines running")"
check "and the low disk"     "1" "$(cad_has "$(ui_value "$BOXES_NOTES_ID")" "disk space: 45 GB free")"

section "agent-vm unavailable: the reason, and nothing to click"
fake_reset
printf '0.1.11\n' > "$FAKE_AGENTVM_DIR/version"
open_window
check "the header says so"             "Boxes are not available" "$(ui_value "$BOXES_HEADER_ID")"
check "  and why, naming the versions" "1" "$(cad_has "$(ui_value "$BOXES_NOTES_ID")" "needs agent-vm 0.2.0 or later")"
check "the picker is off"              "0" "$(ui_enabled "$BOXES_KIND_ID")"
check "New Box is off"                 "0" "$(ui_enabled "$BOXES_NEW_BOX_ID")"
check "New Image is off"               "0" "$(ui_enabled "$BOXES_HEADER_NEW_IMAGE_ID")"
check "nothing was listed"             "0" "$(fake_asked "image list")"

# -----------------------------------------------------------------------------------------
section "the picker switches tables"
fake_reset
open_window
omc_control "$BOXES_KIND_ID" 2
omc_run aichat.boxes.kind.changed
check "Boxes: the boxes table"   "1" "$(ui_visible "$BOXES_BOXES_ID")"
check "  the images table hidden" "0" "$(ui_visible "$BOXES_IMAGES_ID")"
omc_control "$BOXES_KIND_ID" 1
omc_run aichat.boxes.kind.changed
check "Images: back"             "1" "$(ui_visible "$BOXES_IMAGES_ID")"
check "  the boxes hidden"       "0" "$(ui_visible "$BOXES_BOXES_ID")"
check "the detail was cleared"   "Select an image, a box or a job." "$(ui_value "$BOXES_TITLE_ID")"

section "an image: its details and its buttons"
select_image dev-agents
check "titled"                       "Image dev-agents" "$(ui_value "$BOXES_TITLE_ID")"
check "its state"                    "ready" "$(ui_value "$BOXES_SUBTITLE_ID")"
check "the recipe is in the details" "1" "$(cad_has "$(ui_value "$BOXES_DETAIL_ID")" "Claude Code, Codex and opencode")"
check "  the folder"                 "1" "$(cad_has "$(ui_value "$BOXES_DETAIL_ID")" "/Users/you/Library/Application Support/agent-vm/Images/dev-agents")"
check "  and what the need means"    "1" "$(cad_has "$(ui_value "$BOXES_DETAIL_ID")" "Guest update: the image's agent-vm-guest is older")"
check "the image buttons are shown"  "1" "$(ui_visible "$BOXES_IMAGE_BUTTONS_ID")"
check "  the box buttons hidden"     "0" "$(ui_visible "$BOXES_BOX_BUTTONS_ID")"
check "New Box on"                   "1" "$(ui_enabled "$BOXES_IMAGE_NEW_BOX_ID")"
check "Update Guest on"              "1" "$(ui_enabled "$BOXES_IMAGE_UPDATE_ID")"
check "Delete on"                    "1" "$(ui_enabled "$BOXES_IMAGE_DELETE_ID")"
select_image ""
check "a deselection clears it"      "0" "$(ui_visible "$BOXES_IMAGE_BUTTONS_ID")"

section "one selection: a row chosen in one table is let go in the others"
# The detail pane shows one item. A row left highlighted elsewhere could not be clicked to show
# it again: a click on the selected row changes nothing, so no action fires.
deselects() {
    printf '%s %s %s\n' "$(journal_count "$OMC_ACTIONUI_WINDOW_UUID" "$BOXES_IMAGES_ID" omc_deselect)" \
        "$(journal_count "$OMC_ACTIONUI_WINDOW_UUID" "$BOXES_BOXES_ID" omc_deselect)" \
        "$(journal_count "$OMC_ACTIONUI_WINDOW_UUID" "$BOXES_JOBS_ID" omc_deselect)"
}
open_window
select_image dev-agents
check "an image: the boxes and jobs tables let go, the images table keeps its row" "0 1 1" "$(deselects)"
select_job "20260925-120000-abcdef"
check "a job: the images and boxes tables let go" "1 2 1" "$(deselects)"
omc_control "$BOXES_KIND_ID" 1
omc_run aichat.boxes.kind.changed
check "switching tables clears the detail, so every table lets go" "2 3 2" "$(deselects)"

section "a box: its details, logs and buttons"
select_box cadabra-spike
check "titled"                      "Box cadabra-spike" "$(ui_value "$BOXES_TITLE_ID")"
check "stopped"                     "stopped" "$(ui_value "$BOXES_SUBTITLE_ID")"
check "its allowed hosts"           "1" "$(cad_has "$(ui_value "$BOXES_DETAIL_ID")" "allowed:     pack:npm")"
check "its recent programs"         "1" "$(cad_has "$(ui_value "$BOXES_DETAIL_ID")" "/bin/echo ok  -> status 0")"
check "its refused hosts"           "1" "$(cad_has "$(ui_value "$BOXES_DETAIL_ID")" "bag.itunes.apple.com:443  (not in the allowlist)")"
check "  asked of agent-vm with a count" "1" "$(fake_asked "box netlog cadabra-spike --last 8 --denied")"
check "the box buttons are shown"   "1" "$(ui_visible "$BOXES_BOX_BUTTONS_ID")"
check "Start on (stopped)"          "1" "$(ui_enabled "$BOXES_BOX_START_ID")"
check "Stop off"                    "0" "$(ui_enabled "$BOXES_BOX_STOP_ID")"
check "View off (not running)"      "0" "$(ui_enabled "$BOXES_BOX_VIEW_ID")"
check "Shell off (not running)"     "0" "$(ui_enabled "$BOXES_BOX_SHELL_ID")"
check "Delete on (stopped)"         "1" "$(ui_enabled "$BOXES_BOX_DELETE_ID")"

section "Reveal shows the selected item's folder"
/bin/rm -f "$OMCTEST_WORK/opened"
/bin/mkdir -p "$OMCTEST_WORK/boxdir"
/usr/bin/awk -F'\t' -v OFS='\t' -v p="$OMCTEST_WORK/boxdir" '$1 == "cadabra-spike" { $16 = p } { print }' \
    "${TMPDIR:-/tmp}/cadabra-boxes.$OMC_ACTIONUI_WINDOW_UUID.boxes" > "$OMCTEST_WORK/boxes.tmp"
/bin/mv "$OMCTEST_WORK/boxes.tmp" "${TMPDIR:-/tmp}/cadabra-boxes.$OMC_ACTIONUI_WINDOW_UUID.boxes"
omc_run aichat.boxes.reveal
check "the Finder is asked"          "-R $OMCTEST_WORK/boxdir" "$(/bin/cat "$OMCTEST_WORK/opened" 2>/dev/null)"

# -----------------------------------------------------------------------------------------
section "Start: a job, the poll loop, and the lists after it"
fake_reset 1
open_window
select_box cadabra-spike
chains_reset
omc_run aichat.boxes.box.start
check_status "start ran"             0
check "agent-vm was asked to start it, owned by the app" "1" "$(fake_asked "box start cadabra-spike")"
check "a poll loop was asked for"    "1" "$(chain_asked aichat.boxes.poll)"
check "the job is listed as running" "1" "$(ui_rows "$BOXES_JOBS_ID" | /usr/bin/grep -c "^Start cadabra-spike${TAB}running")"
check "the box shows it starting"    "1" "$(ui_rows "$BOXES_BOXES_ID" | /usr/bin/grep -c "^cadabra-spike${TAB}starting...")"
check "Start is off while it runs"   "0" "$(ui_enabled "$BOXES_BOX_START_ID")"
/bin/cp "$FIXTURES/box-status-ready.json" "$FAKE_AGENTVM_DIR/box-cadabra-spike.json"
omc_run aichat.boxes.poll
check_status "the poll loop ended with the job" 0
check "the job is done"              "1" "$(ui_rows "$BOXES_JOBS_ID" | /usr/bin/grep -c "^Start cadabra-spike${TAB}done")"
check "the boxes were read again"    "1" "$([ "$(fake_asked "box list")" -ge 2 ] && echo 1 || echo 0)"
check "the loop's token is released" "" "$(cad_pb_get "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID")"
check "the repainted box row is highlighted again" "0" "$(ui_selection "$BOXES_BOXES_ID")"

section "a second loop takes over; a closed window stops it"
cad_pb_set "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID" "closed"
fake_reset 3
id=$(cad_call_lib aichat.agentvm.library.sh agentvm_box_stop_job try1)
omc_run aichat.boxes.close
check "close marks the loop stopped" "closed" "$(cad_pb_get "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID")"
check "  and forgets the manager"    "" "$(cad_pb_get "cadabra_boxes_manager_window_$OMC_APP_PROCESS_ID")"
check "  and its cache files"        "0" "$(/bin/ls "${TMPDIR:-/tmp}" | /usr/bin/grep -c "cadabra-boxes.$OMC_ACTIONUI_WINDOW_UUID")"
check "but the job goes on"          "running" "$(cad_call_lib aichat.agentvm.library.sh agentvm_jobs | /usr/bin/awk -F'\t' -v id="$id" '$1 == id { print $5 }')"
omc_run aichat.boxes.poll
check "a loop chained before the close does not start" "closed" "$(cad_pb_get "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID")"
cad_call_lib aichat.agentvm.library.sh agentvm_job_cancel "$id"
wait_jobs_done

section "a loop that takes over counts the jobs the old one saw running"
# The old loop saw the job running on its last pass and gave way before it ended; the new loop
# was not told of it by a start. It still counts as ended, so the boxes are read again.
fake_reset 0
open_window
id=$(cad_call_lib aichat.agentvm.library.sh agentvm_box_stop_job try1)
wait_jobs_done
cad_pb_set "cadabra_boxes_seen_$OMC_ACTIONUI_WINDOW_UUID" "$id "
lists_before=$(fake_asked "box list")
omc_run aichat.boxes.poll
check "the boxes were read again"    "$((lists_before + 1))" "$(fake_asked "box list")"
check "  and the loop left nothing running behind" "" "$(cad_pb_get "cadabra_boxes_seen_$OMC_ACTIONUI_WINDOW_UUID")"
cad_call_lib aichat.agentvm.library.sh agentvm_job_forget "$id" >/dev/null

section "a job: its details, Cancel and Remove"
fake_reset 3
open_window
select_box try1
alert_answers_reset
omc_run aichat.boxes.box.start
id=$(/bin/ls "$JOBS" | /usr/bin/tail -1)
select_job "$id"
check "titled with the job"          "Start try1" "$(ui_value "$BOXES_TITLE_ID")"
check "running"                      "running" "$(ui_value "$BOXES_SUBTITLE_ID")"
check "Cancel on"                    "1" "$(ui_enabled "$BOXES_JOB_CANCEL_ID")"
check "Remove off"                   "0" "$(ui_enabled "$BOXES_JOB_FORGET_ID")"
select_box try1
check "choosing a box lets go of the job: Cancel off" "0" "$(ui_enabled "$BOXES_JOB_CANCEL_ID")"
select_job "$id"
alerts_reset
alert_answer 1
omc_run aichat.boxes.job.cancel
check "Cancel asks first"            "1" "$(alerts_count)"
check "  and Keep Running keeps it"  "running" "$(cad_call_lib aichat.agentvm.library.sh agentvm_jobs | /usr/bin/awk -F'\t' -v id="$id" '$1 == id { print $5 }')"
alert_answer 0
omc_run aichat.boxes.job.cancel
wait_jobs_done
omc_run aichat.boxes.poll
select_job "$id"
check "canceled"                     "canceled" "$(ui_value "$BOXES_SUBTITLE_ID")"
check "Remove on now"                "1" "$(ui_enabled "$BOXES_JOB_FORGET_ID")"
omc_run aichat.boxes.job.forget
check "removed from the list"        "0" "$(ui_rows "$BOXES_JOBS_ID" | /usr/bin/grep -c "Start try1")"

section "a failed job shows agent-vm's error"
fake_reset 0
printf 'the guest daemon did not answer; run it again' > "$FAKE_AGENTVM_DIR/fail-image-update-guest"
open_window
select_image dev
omc_run aichat.boxes.image.update.guest
wait_jobs_done
omc_run aichat.boxes.poll
id=$(/bin/ls "$JOBS" | /usr/bin/tail -1)
check "listed as failed, with the reason" "1" "$(ui_rows "$BOXES_JOBS_ID" | /usr/bin/grep -c "failed${TAB}the guest daemon did not answer; run it again")"
select_job "$id"
check "the details carry the whole error" "1" "$(cad_has "$(ui_value "$BOXES_DETAIL_ID")" "the guest daemon did not answer; run it again")"
check "the images were read again after an image job" "1" "$([ "$(fake_asked "image list")" -ge 2 ] && echo 1 || echo 0)"
omc_run aichat.boxes.job.forget

section "refusals reach an alert with agent-vm's words"
fake_reset 0
/bin/cp "$FIXTURES/doctor.json" "$FAKE_AGENTVM_DIR/doctor.json"
open_window
select_box try1
alerts_reset
omc_run aichat.boxes.box.start
check "no free slot: an alert"      "1" "$(alerts_mention "No virtual machine slot is free")"
check "  and no start"              "0" "$(fake_asked "box start")"

# -----------------------------------------------------------------------------------------
section "Delete asks, and Cancel means no"
fake_reset
open_window
select_box try1
alerts_reset
alert_answers_reset
alert_answer 1
omc_run aichat.boxes.box.delete
check "asked"                        "1" "$(alerts_mention "Delete the box try1")"
check "  nothing deleted"            "0" "$(fake_asked "box delete")"
alert_answer 0
omc_run aichat.boxes.box.delete
check "OK deletes"                   "1" "$(fake_asked "box delete try1 --json")"
check "  and the detail is cleared"  "Select an image, a box or a job." "$(ui_value "$BOXES_TITLE_ID")"
printf 'image dev is in use by the box try1' > "$FAKE_AGENTVM_DIR/fail-image-delete"
select_image dev
alerts_reset
alert_answer 0
omc_run aichat.boxes.image.delete
check "an image in use: agent-vm's reason" "1" "$(alerts_mention "image dev is in use by the box try1")"

section "View, View and Control, Shell"
fake_reset
/bin/cp "$FIXTURES/box-status-ready.json" "$FAKE_AGENTVM_DIR/box-try1.json"
open_window
select_box try1
omc_run aichat.boxes.box.view
check "view"            "1" "$(fake_asked "box view try1 --json")"
omc_run aichat.boxes.box.control
check "control"         "1" "$(fake_asked "box view try1 --interactive --json")"
/bin/rm -f "$OMCTEST_WORK/opened"
omc_run aichat.boxes.box.shell
check "Terminal opens the shell file" "-a Terminal $HOME/Library/Application Support/Cadabra/Shells/try1.command" "$(/bin/cat "$OMCTEST_WORK/opened" 2>/dev/null)"

# -----------------------------------------------------------------------------------------
section "New Box from an image: the image chosen, the packs listed"
fake_reset
open_window
manager="$OMC_ACTIONUI_WINDOW_UUID"
select_image dev-node
chains_reset
omc_run aichat.boxes.image.new.box
check "the New Box window is asked for" "1" "$(chain_asked aichat.boxes.box.new)"
omc_window_switch newbox
omc_control_defaults aichat.boxes.box.new
omc_run aichat.boxes.box.new.init
check "the ready images are offered" '["dev","dev-agents","dev-node","dev-xcode","dev-xcode-ios"]' "$(ui_prop "$BOXES_NEW_IMAGE_ID" options)"
check "  from the manager's list, not agent-vm again" "1" "$(fake_asked "image list")"
check "dev-node is chosen"           "3" "$(ui_value "$BOXES_NEW_IMAGE_ID")"
check "the packs are named"          "1" "$(cad_has "$(ui_value "$BOXES_NEW_PACKS_ID")" "Known packs: anthropic, apple-updates")"
check "  none of them marked broken"  "0" "$(cad_has "$(ui_value "$BOXES_NEW_PACKS_ID")" "broken")"
check "the hand-off was read once"   "" "$(cad_pb_get cadabra_boxes_new_image)"

section "Create: the fields become agent-vm's arguments"
omc_control "$BOXES_NEW_NAME_ID" "my-box"
omc_control "$BOXES_NEW_IMAGE_ID" 3
omc_control "$BOXES_NEW_CPUS_ID" "2"
omc_control "$BOXES_NEW_MEMORY_ID" ""
omc_control "$BOXES_NEW_NETWORK_ID" 1
omc_control "$BOXES_NEW_RULES_ID" "  pack:npm
api.example.com:443

"
omc_control "$BOXES_NEW_DISPOSABLE_ID" true
lists_before=$(fake_asked "box list")
omc_run aichat.boxes.box.new.create
check "created with every field" "1" "$(fake_asked "box create my-box --image dev-node --net allowlist --allow pack:npm --allow api.example.com:443 --cpus 2 --disposable --json")"
check "the window closes"        "1" "$(journal_count "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok)"
check "the manager reads its boxes again" "$((lists_before + 1))" "$(fake_asked "box list")"
check "  into its own window"   "1" "$([ "$(journal_count "$manager" "$BOXES_BOXES_ID" omc_table_set_rows_from_stdin)" -ge 1 ] && echo 1 || echo 0)"

section "Create refuses, and says why in the window"
omc_window_switch newbox2
omc_control_defaults aichat.boxes.box.new
omc_run aichat.boxes.box.new.init
omc_control "$BOXES_NEW_NAME_ID" "Bad Name"
omc_control "$BOXES_NEW_IMAGE_ID" 1
omc_run aichat.boxes.box.new.create
check "the reason is under the fields" "1" "$(cad_has "$(ui_value "$BOXES_NEW_STATUS_ID")" "is not a box name agent-vm accepts")"
check "  and the window stays open"    "0" "$(journal_count "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok)"
omc_control "$BOXES_NEW_NAME_ID" "my-box"
omc_run aichat.boxes.box.new.create
check "an existing name: agent-vm's words" "a box named my-box already exists" "$(ui_value "$BOXES_NEW_STATUS_ID")"
omc_control "$BOXES_NEW_NAME_ID" "offline"
omc_control "$BOXES_NEW_NETWORK_ID" 2
omc_control "$BOXES_NEW_RULES_ID" "pack:npm"
omc_control "$BOXES_NEW_DISPOSABLE_ID" false
omc_run aichat.boxes.box.new.create
check "network off takes no rules" "1" "$(fake_asked "box create offline --image dev --net off --json")"

# -----------------------------------------------------------------------------------------
RECIPES="$OMC_APP_BUNDLE_PATH/Contents/Resources/Recipes"

section "a pack agent-vm cannot use is named as broken"
fake_reset
printf '%s' '[{"name":"mine","source":"user","problem":"hosts is not a list of host names"},{"name":"npm","hosts":["registry.npmjs.org"],"source":"built-in"}]' > "$FAKE_AGENTVM_DIR/packs.json"
cad_pb_set cadabra_boxes_new_image "dev-node"
omc_window_switch newbox-broken
omc_control_defaults aichat.boxes.box.new
omc_run aichat.boxes.box.new.init
check "the broken pack says why"      "1" "$(cad_has "$(ui_value "$BOXES_NEW_PACKS_ID")" "mine (broken: hosts is not a list of host names)")"
check "  and the usable one is plain" "1" "$(cad_has "$(ui_value "$BOXES_NEW_PACKS_ID")" "mine (broken: hosts is not a list of host names), npm.")"
/bin/rm -f "$FAKE_AGENTVM_DIR/packs.json"

section "New Image from This...: the window starts from that image"
fake_reset
open_window
manager="$OMC_ACTIONUI_WINDOW_UUID"
select_image dev-node
check "the image offers it"          "1" "$(ui_enabled "$BOXES_IMAGE_NEW_FROM_ID")"
chains_reset
omc_run aichat.boxes.image.new.from
check "the New Image window is asked for" "1" "$(chain_asked aichat.boxes.image.new)"
omc_window_switch newimage
omc_control_defaults aichat.boxes.image.new
omc_run aichat.boxes.image.new.init
check "the ready images are offered"  '["dev","dev-agents","dev-node","dev-xcode","dev-xcode-ios"]' "$(ui_prop "$BOXES_NI_BASE_ID" options)"
check "  starting from an existing image" "2" "$(ui_value "$BOXES_NI_SOURCE_ID")"
check "  dev-node chosen"             "3" "$(ui_value "$BOXES_NI_BASE_ID")"
check "  its picker on"               "1" "$(ui_enabled "$BOXES_NI_BASE_ID")"
check "  and the restore image off"   "0" "$(ui_enabled "$BOXES_NI_IPSW_ID")"
check "the recipes, by description, between None and your own" '["None","ACP agents: Claude Agent ACP, Codex ACP and opencode","Homebrew and Node","Xcode from a .xip you downloaded","Simulator runtimes and Xcode components","A recipe file of your own"]' "$(ui_prop "$BOXES_NI_RECIPE_ID" options)"
check "the hand-off was read once"    "" "$(cad_pb_get cadabra_boxes_new_image_base)"

section "choosing a recipe fills in its inputs and parameters"
omc_control "$BOXES_NI_RECIPE_ID" 2
omc_run aichat.boxes.image.new.recipe.changed
check "ACP agents: each parameter with its default" "claude_acp=0.81.2
codex_acp=1.13.1
opencode=1.18.32
extras=" "$(ui_value "$BOXES_NI_VALUES_ID")"
check "  what each one is"            "1" "$(cad_has "$(ui_value "$BOXES_NI_DECLS_ID")" "claude_acp: version of @agentclientprotocol/claude-agent-acp")"
check "  no input to choose"          "0" "$(ui_enabled "$BOXES_NI_INPUT_BROWSE_ID")"
omc_control "$BOXES_NI_DISK_ID" ""
omc_control "$BOXES_NI_RECIPE_ID" 4
omc_run aichat.boxes.image.new.recipe.changed
check "Xcode: its one input, empty"   "xcode=" "$(ui_value "$BOXES_NI_VALUES_ID")"
check "  marked as a file"            "1" "$(cad_has "$(ui_value "$BOXES_NI_DECLS_ID")" "xcode (a file): an Xcode .xip")"
check "  the input's chooser is on"   "1" "$(ui_enabled "$BOXES_NI_INPUT_BROWSE_ID")"
check "  a 128 GB disk suggested"     "128" "$(ui_value "$BOXES_NI_DISK_ID")"
check "  its own-file field stays off" "0" "$(ui_enabled "$BOXES_NI_RECIPE_FILE_ID")"
printf 'xip' > "$OMCTEST_WORK/Xcode 27.xip"
omc_control "$BOXES_NI_VALUES_ID" "xcode="
omc_dialog_answer choose_file "$OMCTEST_WORK/Xcode 27.xip"
omc_run aichat.boxes.image.new.input.browse
check "Choose Input File... fills the input's line" "xcode=$OMCTEST_WORK/Xcode 27.xip" "$(ui_value "$BOXES_NI_VALUES_ID")"
: > "$OMCTEST_WORK/X\tb.xip"
omc_control "$BOXES_NI_VALUES_ID" "xcode="
omc_dialog_answer choose_file "$OMCTEST_WORK/X\tb.xip"
omc_run aichat.boxes.image.new.input.browse
check "  a backslash in the file's name stays" "xcode=$OMCTEST_WORK/X\tb.xip" "$(ui_value "$BOXES_NI_VALUES_ID")"
omc_control "$BOXES_NI_RECIPE_ID" 1
omc_run aichat.boxes.image.new.recipe.changed
check "None clears them"              "" "$(ui_value "$BOXES_NI_VALUES_ID")"
omc_control "$BOXES_NI_RECIPE_ID" 6
omc_control "$BOXES_NI_RECIPE_FILE_ID" ""
omc_run aichat.boxes.image.new.recipe.changed
check "A recipe file of your own: its field on" "1" "$(ui_enabled "$BOXES_NI_RECIPE_FILE_ID")"
printf '%s' '{"version":1,"description":"Mine","parameters":{"size":{"default":"10"}},"steps":[]}' > "$OMCTEST_WORK/mine.json"
omc_dialog_answer choose_file "$OMCTEST_WORK/mine.json"
omc_run aichat.boxes.image.new.recipe.browse
check "  a chosen file is shown at once" "size=10" "$(ui_value "$BOXES_NI_VALUES_ID")"
check "  and its description"         "Mine" "$(ui_value "$BOXES_NI_ABOUT_ID")"
printf 'not json' > "$OMCTEST_WORK/bad.json"
omc_dialog_answer choose_file "$OMCTEST_WORK/bad.json"
omc_run aichat.boxes.image.new.recipe.browse
check "a file that is not a recipe: says so" "1" "$(cad_has "$(ui_value "$BOXES_NI_STATUS_ID")" "agentvm_json.py recipe")"
check "  and the previous recipe's lines go" "" "$(ui_value "$BOXES_NI_VALUES_ID")"
check "  with its description"        "" "$(ui_value "$BOXES_NI_ABOUT_ID")"

section "Build: the fields become agent-vm's arguments, and the job goes to the Box Manager"
omc_control "$BOXES_NI_NAME_ID" "dev-xcode2"
omc_control "$BOXES_NI_SOURCE_ID" 2
omc_control "$BOXES_NI_BASE_ID" 1
omc_control "$BOXES_NI_RECIPE_ID" 4
omc_control "$BOXES_NI_VALUES_ID" "# the Xcode archive
xcode=$OMCTEST_WORK/Xcode 27.xip
"
omc_control "$BOXES_NI_CPUS_ID" ""
omc_control "$BOXES_NI_MEMORY_ID" ""
omc_control "$BOXES_NI_DISK_ID" "128"
omc_run aichat.boxes.image.new.create
check_status "create ran"             0
check "the window closes"             "1" "$(journal_count "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok)"
wait_jobs_done
check "agent-vm got every field" "image create dev-xcode2 --from dev --input xcode=$OMCTEST_WORK/Xcode 27.xip --recipe $RECIPES/xcode/recipe.json --disk-gb 128 --json" "$(/usr/bin/grep '^image create dev-xcode2' "$FAKE_AGENTVM_DIR/log")"
check "the Box Manager lists the job" "1" "$(ui_rows "$BOXES_JOBS_ID" "$manager" | /usr/bin/grep -c "^Build image dev-xcode2")"
check "  and watches it"              "1" "$(cad_pb_get "cadabra_boxes_watch_$manager" | /usr/bin/grep -c .)"

section "Build refuses, and says why in the window"
omc_window_switch newimage2
omc_control_defaults aichat.boxes.image.new
omc_run aichat.boxes.image.new.init
check "no hand-off: a restore image"  "1" "$(ui_value "$BOXES_NI_SOURCE_ID")"
omc_control "$BOXES_NI_NAME_ID" "base"
omc_control "$BOXES_NI_IPSW_ID" ""
omc_run aichat.boxes.image.new.create
check "no restore image chosen"       "Choose a macOS restore image (.ipsw)." "$(ui_value "$BOXES_NI_STATUS_ID")"
check "  the window stays"            "0" "$(journal_count "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok)"
printf 'ipsw' > "$OMCTEST_WORK/R.ipsw"
omc_control "$BOXES_NI_IPSW_ID" "$OMCTEST_WORK/R.ipsw"
omc_control "$BOXES_NI_NAME_ID" ""
omc_run aichat.boxes.image.new.create
check "no name"                       "The image needs a name." "$(ui_value "$BOXES_NI_STATUS_ID")"
omc_control "$BOXES_NI_NAME_ID" "base"
omc_control "$BOXES_NI_RECIPE_ID" 3
omc_control "$BOXES_NI_VALUES_ID" "just words"
omc_run aichat.boxes.image.new.create
check "a line without ="              "\"just words\" is not a name=value line." "$(ui_value "$BOXES_NI_STATUS_ID")"
omc_control "$BOXES_NI_VALUES_ID" "claude_acpp=latest"
omc_control "$BOXES_NI_RECIPE_ID" 2
omc_run aichat.boxes.image.new.create
check "a misspelled name is refused in the window" "The recipe has no input or parameter named \"claude_acpp\"." "$(ui_value "$BOXES_NI_STATUS_ID")"
omc_control "$BOXES_NI_RECIPE_ID" 3
omc_control "$BOXES_NI_RECIPE_ID" 4
omc_control "$BOXES_NI_VALUES_ID" "xcode="
omc_run aichat.boxes.image.new.create
check "an input with no file"         "The recipe input xcode needs a file." "$(ui_value "$BOXES_NI_STATUS_ID")"
omc_control "$BOXES_NI_VALUES_ID" "xcode=/nowhere/X.xip"
omc_run aichat.boxes.image.new.create
check "a missing input file: the library's reason" "The file for the recipe input xcode, /nowhere/X.xip, does not exist." "$(ui_value "$BOXES_NI_STATUS_ID")"
printf '%s' '{"version":1,"parameters":{"need":{"description":"no default"}},"steps":[]}' > "$OMCTEST_WORK/need.json"
omc_control "$BOXES_NI_RECIPE_ID" 6
omc_control "$BOXES_NI_RECIPE_FILE_ID" "$OMCTEST_WORK/need.json"
omc_control "$BOXES_NI_VALUES_ID" "need="
omc_run aichat.boxes.image.new.create
check "a required parameter left empty" "The recipe parameter need needs a value." "$(ui_value "$BOXES_NI_STATUS_ID")"
omc_control "$BOXES_NI_RECIPE_FILE_ID" "$OMCTEST_WORK/bad.json"
omc_run aichat.boxes.image.new.create
check "a recipe that cannot be read"  "1" "$(cad_has "$(ui_value "$BOXES_NI_STATUS_ID")" "agentvm_json.py recipe")"
check "  and nothing was built"       "0" "$(/bin/cat "$FAKE_AGENTVM_DIR/log" | /usr/bin/grep -c '^image create base' | /usr/bin/tr -d ' ')"

section "the Box Manager coming back to the front starts a loop for running jobs"
fake_reset 3
ui_reset
omc_window_switch manager2
omc_control_defaults aichat.boxes
omc_run aichat.boxes.init
id=$(cad_call_lib aichat.agentvm.library.sh agentvm_box_stop_job try1)
chains_reset
omc_run aichat.boxes.activated
check "a running job and no loop: one is asked for" "1" "$(chain_asked aichat.boxes.poll)"
check "  and the job is listed"      "1" "$(ui_rows "$BOXES_JOBS_ID" | /usr/bin/grep -c "^Stop try1${TAB}running")"
cad_pb_set "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID" "poll-123"
chains_reset
omc_run aichat.boxes.activated
check "a loop already polling: no second one" "0" "$(chain_asked aichat.boxes.poll)"
cad_call_lib aichat.agentvm.library.sh agentvm_job_cancel "$id"
wait_jobs_done
cad_pb_set "cadabra_boxes_poll_$OMC_ACTIONUI_WINDOW_UUID" ""
chains_reset
omc_run aichat.boxes.activated
check "no running job: no loop"       "0" "$(chain_asked aichat.boxes.poll)"
cad_pb_set "cadabra_boxes_watch_$OMC_ACTIONUI_WINDOW_UUID" " $id"
chains_reset
omc_run aichat.boxes.activated
check "a watched job that ended unseen: one pass is asked for" "1" "$(chain_asked aichat.boxes.poll)"
omc_run aichat.boxes.poll
check "  which takes the watch list"  "" "$(cad_pb_get "cadabra_boxes_watch_$OMC_ACTIONUI_WINDOW_UUID")"
chains_reset
omc_run aichat.boxes.activated
check "  and the next activation asks for none" "0" "$(chain_asked aichat.boxes.poll)"

# -----------------------------------------------------------------------------------------
section "images with an old guest daemon: the banner and Update All"
fake_reset
open_window
check "all five fixture images need it" "5 images need a guest update" "$(ui_value "$BOXES_UPDATES_TEXT_ID")"
check "  Update All is shown"          "1" "$(ui_visible "$BOXES_UPDATE_ALL_ID")"
alerts_reset
alert_answers_reset
alert_answer 1
omc_run aichat.boxes.images.update.all
check "it asks first, naming them"     "1" "$(alerts_mention "dev, dev-agents, dev-node, dev-xcode, dev-xcode-ios")"
check "  and Cancel means no"          "0" "$(fake_asked "image update-guest")"
fake_reset 2
open_window
alert_answer 0
omc_run aichat.boxes.images.update.all
check "OK: one job, one agent-vm run for all of them" "1" "$(/bin/cat "$FAKE_AGENTVM_DIR/log" 2>/dev/null | /usr/bin/grep -c '^image update-guest dev dev-agents dev-node dev-xcode dev-xcode-ios --json$' | /usr/bin/tr -d ' ')"
check "  each image shows it"          "5" "$(ui_rows "$BOXES_IMAGES_ID" | /usr/bin/grep -c "${TAB}updating...${TAB}")"
check "  and the banner goes"          "0" "$(ui_visible "$BOXES_UPDATE_ALL_ID")"
select_image dev-node
check "  the image's own Update Guest is off meanwhile" "0" "$(ui_enabled "$BOXES_IMAGE_UPDATE_ID")"
wait_jobs_done
printf '%s' '[{"name":"dev","state":"ready","macOSVersion":"27.0","needs":[]}]' > "$FAKE_AGENTVM_DIR/image-list.json"
open_window
check "no image needs it: no banner"   "" "$(ui_value "$BOXES_UPDATES_TEXT_ID")"
check "  and no button"                "0" "$(ui_visible "$BOXES_UPDATE_ALL_ID")"

section "after a build, an image without Full Disk Access gets the offer"
fake_reset 0
printf '%s' '[{"name":"dev","state":"ready","needs":[]},{"name":"dev-node","state":"ready","needs":[{"kind":"full-disk-access","reason":"not-checked"}]}]' > "$FAKE_AGENTVM_DIR/image-list.json"
open_window
alerts_reset
alert_answers_reset
alert_answer 0
select_image dev-node
omc_run aichat.boxes.image.update.guest
omc_run aichat.boxes.poll
check "the finished job leads to the offer"  "1" "$(alerts_mention "Set up Full Disk Access in dev-node")"
check "  Set Up Now starts the setup job"    "1" "$(fake_asked "image setup dev-node --json")"
check "  which the same loop saw through"    "1" "$(ui_rows "$BOXES_JOBS_ID" | /usr/bin/grep -c "^Set up Full Disk Access in dev-node${TAB}done")"
alerts_reset
alert_answer 1
select_image dev
omc_run aichat.boxes.image.update.guest
omc_run aichat.boxes.poll
check "an image that needs nothing: no offer" "0" "$(alerts_mention "Set up Full Disk Access")"

section "after Update All, one offer at a time, naming the others"
fake_reset 0
printf '%s' '[{"name":"dev","state":"ready","needs":[{"kind":"guest-update"},{"kind":"full-disk-access","reason":"not-checked"}]},{"name":"dev-node","state":"ready","needs":[{"kind":"guest-update"},{"kind":"full-disk-access","reason":"not-checked"}]}]' > "$FAKE_AGENTVM_DIR/image-list.json"
open_window
alerts_reset
alert_answers_reset
alert_answer 0 0
omc_run aichat.boxes.images.update.all
omc_run aichat.boxes.poll
check "one offer for the pair, not one each" "1" "$(alerts_mention "Set up Full Disk Access in")"
check "  for the first image"                "1" "$(alerts_mention "Set up Full Disk Access in dev\?")"
check "  naming the other"                   "1" "$(alerts_mention "It is needed in dev-node too")"
check "  and one setup, not two"             "1" "$(/bin/cat "$FAKE_AGENTVM_DIR/log" | /usr/bin/grep -c '^image setup' | /usr/bin/tr -d ' ')"

section "a guest update that failed partway still gets the offer"
fake_reset 0
printf '%s' '[{"name":"dev","state":"ready","needs":[{"kind":"full-disk-access","reason":"not-checked"}]}]' > "$FAKE_AGENTVM_DIR/image-list.json"
printf 'the guest daemon of dev-node did not answer; dev was updated' > "$FAKE_AGENTVM_DIR/fail-image-update-guest"
open_window
alerts_reset
alert_answers_reset
alert_answer 1
select_image dev
omc_run aichat.boxes.image.update.guest
omc_run aichat.boxes.poll
check "the job failed"                       "1" "$(ui_rows "$BOXES_JOBS_ID" | /usr/bin/grep -c "^Update the guest in dev${TAB}failed")"
check "  and the offer was still made"       "1" "$(alerts_mention "Set up Full Disk Access in dev")"
check "  Later starts nothing"               "0" "$(/bin/cat "$FAKE_AGENTVM_DIR/log" | /usr/bin/grep -c '^image setup' | /usr/bin/tr -d ' ')"

section "Tools > Boxes...: one Box Manager, brought to the front"
fake_reset
ui_reset
omc_window_switch manager3
omc_control_defaults aichat.boxes
omc_run aichat.boxes.init
manager3="$OMC_ACTIONUI_WINDOW_UUID"
chains_reset
omc_run aichat.boxes.open
check "an open Box Manager comes to the front" "1" "$(journal_count "$manager3" omc_window omc_select)"
check "  and no second one opens"      "0" "$(chain_asked aichat.boxes)"
omc_run aichat.boxes.close
chains_reset
omc_run aichat.boxes.open
check "none open: one opens"           "1" "$(chain_asked aichat.boxes)"
check "  and the closed one is not asked to come forward" "1" "$(journal_count "$manager3" omc_window omc_select)"
cad_pb_set "cadabra_boxes_manager_window_999999" "$manager3"
chains_reset
omc_run aichat.boxes.open
check "a uuid another Cadabra process left behind is not read" "1" "$(chain_asked aichat.boxes)"
cad_pb_set "cadabra_boxes_manager_window_999999" ""

section "every view id constant is defined once"
# A later definition silently wins in sh, so a reused name retargets every earlier use: a
# header button's constant once took over the New Box window's image picker.
check "no constant is defined twice" "" "$(/usr/bin/sed -n 's/^\(BOXES_[A-Z_]*_ID\)=.*/\1/p' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh" | /usr/bin/sort | /usr/bin/uniq -d)"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no table was clobbered by a value" "" "$(ui_suspect_writes)"

omctest_end
