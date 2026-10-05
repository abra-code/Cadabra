#!/bin/sh
# Tests/96-start-window.test.sh - the window Cadabra opens at launch: four buttons, each opening
# what the File menu item of the same name opens, after which the start window closes.
#
# What launch itself opens, and the handoff Download Models arms on a Mac with no model, are in
# 98-command-wiring, with the rest of the launch routing.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LAYOUT="$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/aichat.start.json"
MENU="$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/MainMenu.json"

# button <id> <property>  ->  that property of the layout's button.
button() { /usr/bin/jq -r --argjson id "$1" --arg p "$2" '.. | objects | select(.id? == $id) | .properties[$p]' "$LAYOUT"; }
# menu_action <title>  ->  the command the File menu item of that title runs.
menu_action() { /usr/bin/jq -r --arg t "$1" '.. | objects | select(.properties?.title? == $t) | .properties.actionID' "$MENU"; }
# press <id>  ->  the button's handler, run as the window runs it.
press() {
    chains_reset
    cad_journal_reset
    omc_trigger "$1"
    omc_run aichat.start.choose
}

# -----------------------------------------------------------------------------------------
section "the four buttons, in order, each with a large symbol"
check "the titles" "Select Local Model|Select ACP Agent|New Chat|Download Models" \
    "$(/usr/bin/jq -r '[.children[] | select(.type == "Button") | .properties.title] | join("|")' "$LAYOUT")"
check "every button has a symbol"       "4" "$(/usr/bin/jq -r '[.children[] | select(.type == "Button") | select((.properties.systemImage // "") != "")] | length' "$LAYOUT")"
check "  at the large scale"            "4" "$(/usr/bin/jq -r '[.children[] | select(.type == "Button") | select(.properties.imageScale == "large")] | length' "$LAYOUT")"
check "all four run the one handler"    "4" "$(/usr/bin/jq -r '[.children[] | select(.type == "Button") | select(.properties.actionID == "aichat.start.choose")] | length' "$LAYOUT")"

# -----------------------------------------------------------------------------------------
section "each button opens what its File menu item opens, and the window closes"
cad_reset
press 11
check_status "Select Local Model succeeds" 0
check "  the menu item's command"  "aichat.select.local.model" "$(menu_action "Select Local Model")"
check "  is what it asks for"      "1" "$(chain_asked aichat.select.local.model)"
check "  and the window closes"    "1" "$(ui_calls omc_terminate_ok)"
press 12
check_status "Select ACP Agent succeeds" 0
check "Select ACP Agent: the menu item's command" "aichat.select.external.agent" "$(menu_action "Select ACP Agent")"
check "  is what it asks for"      "1" "$(chain_asked aichat.select.external.agent)"
check "  and the window closes"    "1" "$(ui_calls omc_terminate_ok)"
press 13
check_status "New Chat succeeds" 0
check "New Chat: the command of New Chat Window" "aichat.chat.window" "$(menu_action "New Chat Window")"
check "  is what it asks for"      "1" "$(chain_asked aichat.chat.window)"
check "  and the window closes"    "1" "$(ui_calls omc_terminate_ok)"
press 14
check_status "Download Models succeeds" 0
check "Download Models: the menu item's command" "aichat.hf.browse" "$(menu_action "Download Models")"
check "  is what it asks for"      "1" "$(chain_asked aichat.hf.browse)"
check "  and the window closes"    "1" "$(ui_calls omc_terminate_ok)"

# -----------------------------------------------------------------------------------------
section "run by anything but one of the buttons, it does nothing"
press 99
check_status "another view's id: the handler succeeds" 0
check "  nothing is opened"        "0|0|0|0" "$(chain_asked aichat.select.local.model)|$(chain_asked aichat.select.external.agent)|$(chain_asked aichat.chat.window)|$(chain_asked aichat.hf.browse)"
check "  and nothing closes"       "0" "$(ui_calls omc_terminate_ok)"
# A link (cadabra://exe?commandID=aichat.start.choose) runs the command with no window.
chains_reset
cad_journal_reset
omc_trigger 11
( unset OMC_ACTIONUI_WINDOW_UUID; omc_run aichat.start.choose )
check "no window: nothing is opened" "0" "$(chain_asked aichat.select.local.model)"

check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end
