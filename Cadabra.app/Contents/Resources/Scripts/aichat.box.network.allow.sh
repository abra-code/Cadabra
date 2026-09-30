#!/bin/sh
# aichat.box.network.allow.sh
# Allow in This Box...: after a confirmation, the selected refused host's rule is added to the
# box's network rules (agent-vm box network --allow), effective at once. The rule in the hidden
# column is checked against the row's host and port before use (boxnet_selected_rule), since the
# host name came from a program in the box.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
# The chat window may have released its box since the rows were shown: say so, not nothing.
boxnet_context "$window_uuid"
have_box=$?
if [ "$have_box" -ne 0 ]; then
    boxnet_paint "$window_uuid"
    exit 0
fi
rule="$(boxnet_selected_rule "$window_uuid" "$OMC_ACTIONUI_TABLE_801_COLUMN_1_VALUE" \
    "$OMC_ACTIONUI_TABLE_801_COLUMN_2_VALUE" "$OMC_ACTIONUI_TABLE_801_COLUMN_6_VALUE" \
    "$OMC_ACTIONUI_TABLE_801_COLUMN_7_VALUE")"
have_rule=$?
if [ "$have_rule" -ne 0 ]; then
    exit 0
fi
"$alert" --level caution --title "Allow $rule in AgentVM box $boxnet_box?" --ok "Allow" --cancel "Cancel" \
    "Programs in the box, the agent among them, can then connect to $rule. The rule stays with the box: a kept box keeps it for later sessions, and a disposable box is deleted with it."
answer=$?
if [ "$answer" -ne 0 ]; then
    exit 0
fi
said="$(boxnet_allow_in_box "$window_uuid" "$rule")"
allowed=$?
if [ "$allowed" -ne 0 ]; then
    exit 0
fi
boxnet_paint "$window_uuid"
# The row stays listed, and a row that stays selected fires nothing when clicked again, so the
# selection is dropped: the other Allow button on the same host is one click away.
"$dialog" "$window_uuid" "$BOXNET_TABLE_ID" omc_deselect
boxnet_status "$window_uuid" "$said"
