#!/bin/sh
# aichat.box.network.allow.agent.sh
# Allow for <agent>...: after a confirmation, the selected refused host's rule is added to this
# box's network rules at once, as Allow in This Box does, and saved for the agent
# (acp_agent_allow_add), so every new disposable AgentVM box made for it allows the host from
# the start. A kept box keeps the rules it is given, so only the first part matters to it.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
# The chat window may have released its box since the rows were shown: say so, not nothing.
boxnet_context "$window_uuid"
have_box=$?
if [ "$have_box" -ne 0 ] || [ -z "$boxnet_agent_label" ]; then
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
"$alert" --level caution --title "Allow $rule for $boxnet_agent_label?" --ok "Allow" --cancel "Cancel" \
    "Programs in AgentVM box $boxnet_box can connect to $rule at once, and so can programs in every new disposable AgentVM box made for $boxnet_agent_label, the agent among them. The Network window of a chat with $boxnet_agent_label lists the hosts allowed this way, and removes them."
answer=$?
if [ "$answer" -ne 0 ]; then
    exit 0
fi
acp_agent_allow_add "$boxnet_agent" "$rule"
saved=$?
if [ "$saved" -ne 0 ]; then
    boxnet_status "$window_uuid" "Could not save $rule for $boxnet_agent_label in Cadabra's settings, so nothing was changed."
    exit 0
fi
said="$(boxnet_allow_in_box "$window_uuid" "$rule")"
allowed=$?
if [ "$allowed" -ne 0 ]; then
    # Saved, but not in this box: the line under the buttons says why, and the saved list
    # shows the rule for new boxes.
    boxnet_paint_saved "$window_uuid"
    exit 0
fi
boxnet_paint "$window_uuid"
# The row stays listed, and a row that stays selected fires nothing when clicked again, so the
# selection is dropped: the other Allow button on the same host is one click away.
"$dialog" "$window_uuid" "$BOXNET_TABLE_ID" omc_deselect
boxnet_status "$window_uuid" "$said Saved for $boxnet_agent_label: new boxes allow it too."
exit 0
