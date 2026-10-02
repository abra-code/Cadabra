#!/bin/sh
# aichat.box.network.saved.remove.sh
# Remove...: after a confirmation, the selected host is no longer saved for the agent, so new
# AgentVM boxes made for it do not allow it. Boxes that already have the rule keep it: this box
# until it is deleted, a kept box until its rules are edited in the AgentVM app.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
rule="$OMC_ACTIONUI_TABLE_808_COLUMN_1_VALUE"
boxnet_context "$window_uuid"
have_box=$?
if [ "$have_box" -ne 0 ] || [ -z "$boxnet_agent_label" ] || [ -z "$rule" ]; then
    boxnet_paint "$window_uuid"
    exit 0
fi
"$alert" --level caution --title "Stop allowing $rule for $boxnet_agent_label?" --ok "Remove" --cancel "Cancel" \
    "New disposable AgentVM boxes made for $boxnet_agent_label no longer allow $rule, unless it is among the hosts the agent comes with. Boxes that already allow it, AgentVM box $boxnet_box among them, keep the rule."
answer=$?
if [ "$answer" -ne 0 ]; then
    exit 0
fi
acp_agent_allow_remove "$boxnet_agent" "$rule"
removed=$?
boxnet_paint_saved "$window_uuid"
if [ "$removed" -ne 0 ]; then
    boxnet_status "$window_uuid" "Could not remove $rule for $boxnet_agent_label from Cadabra's settings."
else
    boxnet_status "$window_uuid" "New boxes for $boxnet_agent_label no longer allow $rule."
fi
