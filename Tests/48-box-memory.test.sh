#!/bin/sh
# Tests/48-box-memory.test.sh - AgentVM box memory in the memory warnings: running boxes count
# with running models when a model is loaded (warn_ram_pressure_for_new_model), and a box about
# to start for a chat is checked the same way before it starts (chat_engine_box_memory_check,
# warn_ram_pressure_for_new_box).
#
# agent-vm is fake_agent_vm.sh; this Mac's memory is CADABRA_RAM_BYTES, so the numbers do not
# depend on the Mac the tests run on. POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
GB=1073741824
CADABRA_AGENT_VM="$FAKE"
CADABRA_RAM_BYTES=$((16 * GB))
export FAKE_AGENTVM_DIR CADABRA_AGENT_VM CADABRA_RAM_BYTES
unset AGENT_VM_HOME
CAD_PREFS_OVERRIDE="$OMCTEST_WORK/no-such-registry.plist"
export CAD_PREFS_OVERRIDE

# boxes <state of cadabra-spike, 4 GB> <state of try1, 8 GB>  ->  the fake's box list.
boxes() {
    /usr/bin/jq --arg a "$1" --arg b "$2" \
        '.[0].state = $a | .[0].running = ($a == "running") | .[1].state = $b | .[1].running = ($b == "running")' \
        "$FIXTURES/box-list.json" > "$FAKE_AGENTVM_DIR/box-list.json"
}
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
    boxes stopped stopped
}
# engine <function> [args...]  ->  its status, with the chat engine's libraries.
engine() {
    ( . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.chat.engine.library.sh" >/dev/null 2>&1
      prefs="$CAD_PREFS_OVERRIDE"
      "$@" >/dev/null 2>&1
      printf '%s\n' "$?" )
}

# -----------------------------------------------------------------------------------------
section "the running boxes' memory"
fake_reset
check "none running: nothing"            "0" "$(cad_call_lib aichat.agentvm.library.sh agentvm_running_boxes_bytes)"
boxes running stopped
check "one running box: its memory"      "$((4 * GB))" "$(cad_call_lib aichat.agentvm.library.sh agentvm_running_boxes_bytes)"
boxes running running
check "two: both"                        "$((12 * GB))" "$(cad_call_lib aichat.agentvm.library.sh agentvm_running_boxes_bytes)"
printf 'the store is locked\n' > "$FAKE_AGENTVM_DIR/fail-box-list"
check "a list agent-vm cannot give counts nothing" "0" "$(cad_call_lib aichat.agentvm.library.sh agentvm_running_boxes_bytes)"
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-box-list"
check "no agent-vm here counts nothing"  "0" "$( ( CADABRA_AGENT_VM="$OMCTEST_WORK/nowhere"; export CADABRA_AGENT_VM; cad_call_lib aichat.agentvm.library.sh agentvm_running_boxes_bytes ) )"
boxes starting unresponsive
check "starting and not answering count too" "$((12 * GB))" "$(cad_call_lib aichat.agentvm.library.sh agentvm_running_boxes_bytes)"
boxes stopping stopped
check "a box stopping does not"          "0" "$(cad_call_lib aichat.agentvm.library.sh agentvm_running_boxes_bytes)"
boxes running running
check "the box left out is not counted"  "$((8 * GB))" "$(cad_call_lib aichat.agentvm.library.sh agentvm_running_boxes_bytes cadabra-spike)"

section "loading a model counts the running boxes"
# A 16 GB Mac warns above 12 GB.
fake_reset
alerts_reset; alert_answers_reset
check "a 6 GB model with no box running loads" "0" "$(cad_model_call warn_ram_pressure_for_new_model $((6 * GB)) "Mid-8B"; echo $?)"
check "  without a question"             "0" "$(alerts_count)"
boxes stopped running
alert_answer 1
check "the same model beside a running 8 GB box asks, and Cancel refuses" "1" "$(cad_model_call warn_ram_pressure_for_new_model $((6 * GB)) "Mid-8B"; echo $?)"
check "  asked once"                     "1" "$(alerts_count)"
check "  naming the running boxes"       "1" "$(alerts_mention 'Running boxes:   8.0 GB')"
check "  with no models row when none runs" "0" "$(alerts_mention 'Running models')"
check "  the combined total"             "1" "$(alerts_mention 'Combined total:  14.0 GB')"
check "  and suggesting a box be stopped" "1" "$(alerts_mention 'stopping an AgentVM box first')"
alerts_reset; alert_answers_reset
alert_answer 0
check "Load Anyway goes on"              "0" "$(cad_model_call warn_ram_pressure_for_new_model $((6 * GB)) "Mid-8B"; echo $?)"
alerts_reset; alert_answers_reset
alert_answer 1
: > "$FAKE_AGENTVM_DIR/log"
check "a model too big alone still asks, before any box is listed" "1" "$(cad_model_call warn_ram_pressure_for_new_model $((13 * GB)) "Big-30B"; echo $?)"
check "  in the words it had"            "1" "$(alerts_mention 'likely exceeds what your Mac can load')"
check "  and agent-vm was not asked for its boxes" "0" "$(/usr/bin/awk '/^box list/ { n++ } END { print n + 0 }' "$FAKE_AGENTVM_DIR/log")"

section "starting a chat's box checks its memory first"
fake_reset
alerts_reset; alert_answers_reset
check "a new 8 GB box on a 16 GB Mac with nothing running starts" "0" "$(engine chat_engine_box_memory_check new:dev)"
check "  without a question"             "0" "$(alerts_count)"
boxes running stopped
alert_answer 1
check "beside a running 4 GB box on a 14 GB Mac it asks, and Cancel refuses" "1" "$(CADABRA_RAM_BYTES=$((14 * GB)) engine chat_engine_box_memory_check new:dev)"
check "  naming the image"               "1" "$(alerts_mention 'Starting a new AgentVM box from dev (8.0 GB) will likely cause high memory pressure')"
check "  the running box and the new one" "1|1" "$(alerts_mention 'Running boxes:   4.0 GB')|$(alerts_mention 'New box:         8.0 GB')"
check "  with Start Anyway"              "1" "$(alerts_mention 'Start Anyway')"
alerts_reset; alert_answers_reset
alert_answer 0
check "Start Anyway goes on"             "0" "$(CADABRA_RAM_BYTES=$((14 * GB)) engine chat_engine_box_memory_check new:dev)"
REGISTRY="$HOME/Library/Application Support/Cadabra/box-sessions.tsv"
/bin/mkdir -p "$(/usr/bin/dirname "$REGISTRY")"
printf 'w1\tcadabra-spike\tyes\t/tmp/p\tno\t1\n' > "$REGISTRY"
alerts_reset; alert_answers_reset
check "the window's own disposable box, about to go, is not counted" "0" "$(CADABRA_RAM_BYTES=$((14 * GB)) engine chat_engine_box_memory_check new:dev w1)"
check "  so nothing is asked"            "0" "$(alerts_count)"
printf 'w1\tcadabra-spike\tno\t/tmp/p\tno\t1\n' > "$REGISTRY"
alert_answer 1
check "  but its kept box, which stays, is" "1" "$(CADABRA_RAM_BYTES=$((14 * GB)) engine chat_engine_box_memory_check new:dev w1)"
/bin/rm -f "$REGISTRY"
alerts_reset; alert_answers_reset
alert_answer 1
check "a box bigger than a small Mac can spare asks alone" "1" "$(CADABRA_RAM_BYTES=$((8 * GB)) engine chat_engine_box_memory_check box:try1)"
check "  suggesting a smaller box"       "1" "$(alerts_mention 'Give the box less memory')"
check "  and naming the kept box"        "1" "$(alerts_mention 'the AgentVM box try1 (8.0 GB)')"
boxes stopped running
alerts_reset; alert_answers_reset
check "a kept box that runs already adds nothing" "0" "$(CADABRA_RAM_BYTES=$((8 * GB)) engine chat_engine_box_memory_check box:try1)"
check "  and asks nothing"               "0" "$(alerts_count)"
check "an image agent-vm does not know asks nothing" "0" "$(CADABRA_RAM_BYTES=$((8 * GB)) engine chat_engine_box_memory_check new:no-such-image)"
check "neither a new nor a kept box: nothing" "0" "$(CADABRA_RAM_BYTES=$((8 * GB)) engine chat_engine_box_memory_check mac)"
check "  still no question"              "0" "$(alerts_count)"

omctest_end
