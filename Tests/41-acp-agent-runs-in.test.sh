#!/bin/sh
# Tests/41-acp-agent-runs-in.test.sh - the Select ACP Agent window's "Runs in" and level pickers:
# which places are offered (this Mac, kept boxes, a disposable box from each ready image), how
# each agent's stored choice is shown and followed by the rest of the window, and what Continue
# stores and where it goes next. agent-vm is fake_agent_vm.sh, as in tests 45-48.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
CADABRA_AGENT_VM="$FAKE"
export FAKE_AGENTVM_DIR CADABRA_AGENT_VM
unset AGENT_VM_HOME
TAB=$(printf '\t')

fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
}

# options  ->  the Runs in picker's option tags, space-joined.
options() {
    ui_prop "$RUN_IN_PICKER_ID" options | "$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -c \
        'import json, sys; print(" ".join(o.get("tag", "|" + o.get("section", "-")) for o in json.load(sys.stdin)))' 2>&1
}

# continue_with <agent id> <command> <run-in> <level>  ->  Continue pressed with that agent on
# screen and those picker values.
continue_with() {
    omc_control "$PANE_OWNER_ID" "$1"
    omc_table_cell "$TABLE_ID" 4 "$1"
    omc_table_cell "$TABLE_ID" 3 "$2"
    omc_control "$COMMAND_FIELD_ID" "$2"
    omc_control "$USE_TOOLS_PICKER_ID" true
    omc_control "$RUN_IN_PICKER_ID" "$3"
    omc_control "$LEVEL_PICKER_ID" "$4"
    chains_reset
    omc_run aichat.select.external.agent.ok
}

section "the ids this file drives are the ones the window declares"
check "the row, the two pickers, Keys... and Set Up AgentVM..." "31 32 34 36 37" "$BOX_ROW_ID $RUN_IN_PICKER_ID $LEVEL_PICKER_ID $KEYS_BUTTON_ID $SETUP_BUTTON_ID"

section "the window offers this Mac, the kept boxes and a disposable box from each ready image"
cad_reset
fake_reset
ui_reset
omc_run aichat.select.external.agent.init
check "the row is shown"                 "1" "$(ui_visible "$BOX_ROW_ID")"
check "the places, grouped" \
    "mac |Kept AgentVM boxes box:cadabra-spike box:try1 |New disposable AgentVM box from new:dev new:dev-agents new:dev-node new:dev-xcode new:dev-xcode-ios" \
    "$(options)"
check "an agent with no choice runs on this Mac" "mac" "$(ui_value "$RUN_IN_PICKER_ID")"
check "  with no level picker"           "0" "$(ui_visible "$LEVEL_PICKER_ID")"
check "  and no Keys..."                 "0" "$(ui_visible "$KEYS_BUTTON_ID")"
check "  and tools on"                   "true|1" "$(ui_value "$USE_TOOLS_PICKER_ID")|$(ui_enabled "$USE_TOOLS_PICKER_ID")"

section "an agent set to a box shows its box and level, with tools off"
cad_reset
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp new:dev-agents
cad_call acp_agent_set_level claude-code-acp ask
ui_reset
omc_run aichat.select.external.agent.init
check "the stored place"                 "new:dev-agents" "$(ui_value "$RUN_IN_PICKER_ID")"
check "the stored level, shown"          "ask|1" "$(ui_value "$LEVEL_PICKER_ID")|$(ui_visible "$LEVEL_PICKER_ID")"
check "tools still offered in a box"     "1" "$(ui_enabled "$USE_TOOLS_PICKER_ID")"
check "Keys... offered"                  "1" "$(ui_visible "$KEYS_BUTTON_ID")"

section "a place that is gone stays shown, never replaced by this Mac"
cad_call acp_agent_set_run_in claude-code-acp box:gone
ui_reset
omc_run aichat.select.external.agent.init
check "it is still the value"            "box:gone" "$(ui_value "$RUN_IN_PICKER_ID")"
check "  offered as not found"           "1" "$(cad_has "$(ui_prop "$RUN_IN_PICKER_ID" options)" '"gone (not found)"')"

section "where boxes cannot be used, an agent on this Mac gets no row and an empty picker"
fake_reset
printf '0.1.0\n' > "$FAKE_AGENTVM_DIR/version"
cad_call acp_agent_set_run_in claude-code-acp mac
ui_reset
omc_run aichat.select.external.agent.init
check "the row is hidden"                "0" "$(ui_visible "$BOX_ROW_ID")"
check "  and the picker holds nothing"   "" "$(ui_value "$RUN_IN_PICKER_ID")"
fake_reset

section "where the AgentVM app is the next step, the row shows This Mac and the way there"
# No seam and no setting: the installed agent-vm, which the scratch home does not have.
cad_reset
fake_reset
unset CADABRA_AGENT_VM
ui_reset
omc_run aichat.select.external.agent.init
check "nothing installed: the row shows" "1" "$(ui_visible "$BOX_ROW_ID")"
check "  offering this Mac only"         "mac" "$(options)"
check "  and Set Up AgentVM..."          "1" "$(ui_visible "$SETUP_BUTTON_ID")"
check "  agent-vm was never run"         "" "$(/bin/cat "$FAKE_AGENTVM_DIR/log" 2>/dev/null)"
omc_run aichat.select.external.agent.cancel
CADABRA_AGENT_VM="$FAKE"
export CADABRA_AGENT_VM
printf '[]\n' > "$FAKE_AGENTVM_DIR/box-list.json"
printf '[]\n' > "$FAKE_AGENTVM_DIR/image-list.json"
ui_reset
omc_run aichat.select.external.agent.init
check "no box and no image yet: the same" "1|mac|1" "$(ui_visible "$BOX_ROW_ID")|$(options)|$(ui_visible "$SETUP_BUTTON_ID")"
omc_run aichat.select.external.agent.cancel
fake_reset
ui_reset
omc_run aichat.select.external.agent.init
check "with boxes to choose: no button"  "1|0" "$(ui_visible "$BOX_ROW_ID")|$(ui_visible "$SETUP_BUTTON_ID")"
omc_run aichat.select.external.agent.cancel
# The button's handler: the AgentVM app by its link, and nothing for a link with no window.
OPENED="$OMCTEST_WORK/opened"
CADABRA_OPEN="$OMCTEST_WORK/fake_open.sh"
export CADABRA_OPEN
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$OPENED" > "$CADABRA_OPEN"
/bin/chmod +x "$CADABRA_OPEN"
/bin/rm -f "$OPENED"
omc_run aichat.agentvm.app.open
check "Set Up AgentVM... opens the app"  "agentvm://status" "$(/bin/cat "$OPENED" 2>/dev/null)"
/bin/rm -f "$OPENED"
saved_uuid="$OMC_ACTIONUI_WINDOW_UUID"
OMC_ACTIONUI_WINDOW_UUID=""
ACTIONUI_WINDOW_UUID=""
export OMC_ACTIONUI_WINDOW_UUID ACTIONUI_WINDOW_UUID
omc_run aichat.agentvm.app.open
check "  run with no window, it opens nothing" "" "$(/bin/cat "$OPENED" 2>/dev/null)"
OMC_ACTIONUI_WINDOW_UUID="$saved_uuid"
ACTIONUI_WINDOW_UUID="$saved_uuid"
export OMC_ACTIONUI_WINDOW_UUID ACTIONUI_WINDOW_UUID
unset CADABRA_OPEN

section "where boxes cannot be used, an agent set to a box can still be moved back to this Mac"
cad_reset
fake_reset
printf '0.1.0\n' > "$FAKE_AGENTVM_DIR/version"
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp box:try1
ui_reset
omc_run aichat.select.external.agent.init
check "the row shows"                    "1" "$(ui_visible "$BOX_ROW_ID")"
check "  offering This Mac and the stored place only" "mac box:try1" "$(options | /usr/bin/sed 's/ |[^ ]*//g')"
check "  with the stored place chosen"   "box:try1" "$(ui_value "$RUN_IN_PICKER_ID")"
continue_with claude-code-acp "claude-agent-acp" mac free
check "choosing This Mac stores it"      "mac" "$(cad_call acp_agent_run_in claude-code-acp)"
cad_reset
fake_reset

section "changing the place changes the rest of the window, and stores nothing"
cad_call acp_agent_set_run_in claude-code-acp mac
omc_control "$PANE_OWNER_ID" claude-code-acp
omc_control "$RUN_IN_PICKER_ID" box:try1
omc_run aichat.select.external.agent.runin.changed
check "a box shows the level picker"     "1" "$(ui_visible "$LEVEL_PICKER_ID")"
check "  and leaves tools as chosen, offered" "true|1" "$(ui_value "$USE_TOOLS_PICKER_ID")|$(ui_enabled "$USE_TOOLS_PICKER_ID")"
check "  with nothing stored yet"        "mac" "$(cad_call acp_agent_run_in claude-code-acp)"
check "  and Keys... for Claude"         "1" "$(ui_visible "$KEYS_BUTTON_ID")"
omc_control "$RUN_IN_PICKER_ID" mac
omc_run aichat.select.external.agent.runin.changed
check "this Mac hides it again"          "0|1" "$(ui_visible "$LEVEL_PICKER_ID")|$(ui_enabled "$USE_TOOLS_PICKER_ID")"
check "  and Keys..."                    "0" "$(ui_visible "$KEYS_BUTTON_ID")"
omc_control "$PANE_OWNER_ID" "custom:1"
omc_control "$RUN_IN_PICKER_ID" box:try1
omc_run aichat.select.external.agent.runin.changed
check "a saved agent in a box has no Keys..." "1|0" "$(ui_visible "$LEVEL_PICKER_ID")|$(ui_visible "$KEYS_BUTTON_ID")"

section "Keys... opens the Keys window for the agent on screen and the place the picker names"
chains_reset
omc_control "$PANE_OWNER_ID" codex-acp
omc_control "$RUN_IN_PICKER_ID" box:try1
omc_run aichat.select.external.agent.keys
check "the window is asked for"          "1" "$(chain_asked aichat.agent.keys)"
check "  handed the agent and the place, stored or not" "codex-acp${TAB}box:try1" "$(cad_pb_get cadabra_agent_keys_request)"
cad_pb_set cadabra_agent_keys_request ""
chains_reset
omc_control "$PANE_OWNER_ID" ""
omc_run aichat.select.external.agent.keys
check "with the pane mid-repaint, nothing opens" "0|" "$(chain_asked aichat.agent.keys)|$(cad_pb_get cadabra_agent_keys_request)"
omc_control "$PANE_OWNER_ID" "custom:1"
omc_run aichat.select.external.agent.keys
check "  nor for a saved agent"          "0" "$(chain_asked aichat.agent.keys)"

section "each agent's place follows the selection"
cad_call acp_agent_set_run_in opencode box:try1
ui_reset
# Opened again: the window above read the places while agent-vm was too old, and a window keeps
# what it read (agent_load_places).
omc_run aichat.select.external.agent.init
omc_table_cell "$TABLE_ID" 3 "opencode acp"
omc_table_cell "$TABLE_ID" 4 opencode
omc_run aichat.select.external.agent.selection.changed
check "opencode's box"                   "box:try1" "$(ui_value "$RUN_IN_PICKER_ID")"
omc_table_cell "$TABLE_ID" 3 "claude-agent-acp"
omc_table_cell "$TABLE_ID" 4 claude-code-acp
omc_run aichat.select.external.agent.selection.changed
check "then Claude's Mac"                "mac" "$(ui_value "$RUN_IN_PICKER_ID")"

section "Continue with a box stores it, turns tools off and goes through the project step"
cad_reset
ui_reset
continue_with claude-code-acp "claude-agent-acp" new:dev-agents plan
check "the place is stored for the agent" "new:dev-agents" "$(cad_call acp_agent_run_in claude-code-acp)"
check "  and the level"                  "plan" "$(cad_call acp_agent_level claude-code-acp)"
check "the launch carries the tools chosen (Cadabra's servers, copied into the box)" "true" "$(cad_pb_get aichatv2_launch_queue | /usr/bin/awk -F"|" "{ print \$2 }")"
check "the project step comes next"      "1|0" "$(chain_asked aichat.mcp.servers)|$(chain_asked aichat.chat)"

section "Continue on this Mac keeps the old routes"
continue_with claude-code-acp "claude-agent-acp" mac free
check "the place is stored"              "mac" "$(cad_call acp_agent_run_in claude-code-acp)"
check "tools on still go through the servers step" "1" "$(chain_asked aichat.mcp.servers)"
omc_control "$PANE_OWNER_ID" claude-code-acp
omc_control "$USE_TOOLS_PICKER_ID" false
omc_control "$RUN_IN_PICKER_ID" mac
chains_reset
omc_run aichat.select.external.agent.ok
check "tools off go straight to the chat" "0|1" "$(chain_asked aichat.mcp.servers)|$(chain_asked aichat.chat)"

section "Continue refuses a level the agent cannot be held to, and stores nothing"
cad_reset
ui_reset
continue_with codex-acp "codex-acp" box:try1 plan
check "Codex's plan level is refused, with the reason" "1" "$(cad_has "$(ui_value "$RESULT_TEXT_ID")" 'Codex has no plan-only mode')"
check "  nothing is stored"              "mac|" "$(cad_call acp_agent_run_in codex-acp)|$(cad_get /agents/external/id)"
check "  and the window stays"           "0|0" "$(chain_asked aichat.mcp.servers)|$(chain_asked aichat.chat)"
continue_with "custom:1" "my-agent --acp" new:dev ask
check "asking is refused for an agent with no recipe" "1" "$(cad_has "$(ui_value "$RESULT_TEXT_ID")" 'does not know how to make this agent ask')"
continue_with codex-acp "codex-acp" damaged free
check "an unreadable place is refused"   "1" "$(cad_has "$(ui_value "$RESULT_TEXT_ID")" 'could not be read')"

section "Continue asks before running a program from the home folder in a box"
cad_reset
fake_reset
ui_reset
alerts_reset
alert_answers_reset
alert_answer 0
continue_with "custom:1" "$HOME/.opencode/bin/opencode acp" new:dev free
check "it asks"                          "1" "$(alerts_mention 'which is in your home folder on this Mac')"
check "  naming the program"             "1" "$(alerts_mention "starts $HOME/.opencode/bin/opencode,")"
check "Edit Command stores nothing"      "mac|" "$(cad_call acp_agent_run_in custom)|$(cad_get /agents/external/id)"
check "  and the window stays"           "0|0" "$(chain_asked aichat.mcp.servers)|$(chain_asked aichat.chat)"
check "  saying what to change"          "1" "$(cad_has "$(ui_value "$RESULT_TEXT_ID")" "the program's name in the AgentVM box")"
alert_answer 255
continue_with "custom:1" "$HOME/.opencode/bin/opencode acp" new:dev free
check "an alert that failed stores nothing either" "mac|0" "$(cad_call acp_agent_run_in custom)|$(chain_asked aichat.mcp.servers)"
alert_answer 2
continue_with "custom:1" "$HOME/.opencode/bin/opencode acp" new:dev free
check "Continue Anyway stores the box"   "new:dev" "$(cad_call acp_agent_run_in custom)"
check "  and goes on to the project step" "1" "$(chain_asked aichat.mcp.servers)"
alerts_reset
alert_answers_reset
continue_with "custom:1" "$HOME/.opencode/bin/opencode acp" mac free
check "on this Mac nothing is asked"     "0|mac" "$(alerts_count)|$(cad_call acp_agent_run_in custom)"
continue_with "custom:1" "my-agent --acp" new:dev free
check "nor for a plain program name in a box" "0|new:dev" "$(alerts_count)|$(cad_call acp_agent_run_in custom)"
continue_with opencode "opencode acp" new:dev free
check "nor for an agent the catalog gives its own box command" "0|new:dev" "$(alerts_count)|$(cad_call acp_agent_run_in opencode)"
cad_reset
alerts_reset
continue_with "custom:1" "~/.opencode/bin/opencode acp" new:dev free
check "a program written with ~ is refused, without a question" "0|mac|" "$(alerts_count)|$(cad_call acp_agent_run_in custom)|$(cad_get /agents/external/id)"
check "  saying ~ is not expanded"       "1" "$(cad_has "$(ui_value "$RESULT_TEXT_ID")" 'Cadabra does not expand ~ in a command, so ~/.opencode/bin/opencode cannot start.')"
check "  and the window stays"           "0|0" "$(chain_asked aichat.mcp.servers)|$(chain_asked aichat.chat)"

section "where boxes cannot be used, Continue leaves the stored place alone"
cad_reset
cad_call acp_agent_set_run_in claude-code-acp box:try1
continue_with claude-code-acp "claude-agent-acp" "" free
check "the box stays the agent's place"  "box:try1" "$(cad_call acp_agent_run_in claude-code-acp)"
check "  and the launch goes on; chat init refuses it there" "1" "$(chain_asked aichat.mcp.servers)"

section "an edited command, where boxes cannot be used, keeps the place it was shown with"
# Committed as the bare "custom" id, whose own place (This Mac here) would otherwise apply.
cad_reset
cad_call acp_agent_set_run_in claude-code-acp box:try1
cad_call acp_agent_set_level claude-code-acp ask
cad_call acp_agent_set_run_in custom mac
omc_control "$PANE_OWNER_ID" claude-code-acp
omc_table_cell "$TABLE_ID" 4 claude-code-acp
omc_table_cell "$TABLE_ID" 3 "claude-agent-acp"
omc_control "$COMMAND_FIELD_ID" "claude-agent-acp --verbose"
omc_control "$USE_TOOLS_PICKER_ID" true
omc_control "$RUN_IN_PICKER_ID" ""
omc_control "$LEVEL_PICKER_ID" free
chains_reset
omc_run aichat.select.external.agent.ok
check "it is stored as an unnamed command" "custom" "$(cad_get /agents/external/id)"
check "  in the agent's box, at its level" "box:try1|ask" "$(cad_call acp_agent_run_in custom)|$(cad_call acp_agent_level custom)"

section "removing the configured agent keeps its place for the command that stays"
cad_reset
fake_reset
removed_id="$(cad_call acp_custom_add "Boxed" "my-agent --acp")"
cad_call acp_agent_store "$removed_id" "my-agent --acp" >/dev/null 2>&1
cad_call acp_agent_set_run_in "$removed_id" box:try1
cad_call acp_agent_set_run_in custom mac
ui_reset
omc_control "$PANE_OWNER_ID" "$removed_id"
omc_run aichat.select.external.agent.remove
check "the id is demoted"                "custom" "$(cad_get /agents/external/id)"
check "  and keeps the box"              "box:try1" "$(cad_call acp_agent_run_in custom)"
check "the Runs in row shows it"         "box:try1" "$(ui_value "$RUN_IN_PICKER_ID")"

section "+ shows the new agent's place, not the previous row's"
omc_run aichat.select.external.agent.add
check "a new agent runs on this Mac"     "mac" "$(ui_value "$RUN_IN_PICKER_ID")"
check "  with tools offered again"       "1" "$(ui_enabled "$USE_TOOLS_PICKER_ID")"

section "agent-vm is asked once per window, not on every click"
cad_reset
fake_reset
ui_reset
omc_run aichat.select.external.agent.init
check "opening the window lists the boxes once" "1" "$(/usr/bin/grep -c '^box list' "$FAKE_AGENTVM_DIR/log")"
omc_table_cell "$TABLE_ID" 3 "opencode acp"
omc_table_cell "$TABLE_ID" 4 opencode
omc_run aichat.select.external.agent.selection.changed
omc_table_cell "$TABLE_ID" 3 "claude-agent-acp"
omc_table_cell "$TABLE_ID" 4 claude-code-acp
omc_run aichat.select.external.agent.selection.changed
check "  and clicking rows asks again for nothing" "1|1" "$(/usr/bin/grep -c '^box list' "$FAKE_AGENTVM_DIR/log")|$(/usr/bin/grep -c '^image list' "$FAKE_AGENTVM_DIR/log")"
check "  while the places are still offered" "1" "$(cad_has "$(ui_prop "$RUN_IN_PICKER_ID" options)" '"new:dev-agents"')"
# This window's file exactly: test files run side by side, and a glob can find another's.
places_file=$(cad_call_lib aichat.select.external.agent.library.sh agent_places_file)
check "  kept in a file for the window"  "1" "$([ -f "$places_file" ] && echo 1 || echo 0)"
omc_run aichat.select.external.agent.cancel
check "Cancel removes it"                "0" "$([ -f "$places_file" ] && echo 1 || echo 0)"

section "an unreadable level is refused for a box and never stored as the freest"
cad_reset
fake_reset
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp box:try1
cad_call acp_agent_set_level claude-code-acp ask
"$cad_plister" set dict "$cad_settings" /agents/level/claude-code-acp >/dev/null 2>&1
ui_reset
omc_run aichat.select.external.agent.init
check "the level picker selects nothing" "" "$(ui_value "$LEVEL_PICKER_ID")"
continue_with claude-code-acp "claude-agent-acp" box:try1 ""
check "Continue in a box is refused"     "1" "$(cad_has "$(ui_value "$RESULT_TEXT_ID")" 'how much this agent asks')"
check "  and the level is not overwritten" "damaged" "$(cad_call acp_agent_level claude-code-acp)"
continue_with claude-code-acp "claude-agent-acp" mac ""
check "on this Mac the default is kept"  "mac|free" "$(cad_call acp_agent_run_in claude-code-acp)|$(cad_call acp_agent_level claude-code-acp)"

omctest_end
