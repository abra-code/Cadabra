#!/bin/sh
# aichat.agent.keys.use.changed.sh
# The agent gets picker changed: stored at once for the agent. Programmatic updates of the picker
# can fire this with a value that is no choice, or the stored one, and both change nothing.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agent.keys.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
keys_context "$window_uuid" || exit 0
value="$OMC_ACTIONUI_VIEW_705_VALUE"
if [ "$value" != "none" ] && ! keys_is_agent_key "$keys_agent" "$value"; then
    exit 0
fi
if [ "$value" = "$(acp_agent_secret "$keys_agent")" ]; then
    exit 0
fi
acp_agent_set_secret "$keys_agent" "$value"
status=$?
if [ "$status" -ne 0 ]; then
    keys_status "$window_uuid" "Could not save the choice: Cadabra's settings could not be written."
    exit 0
fi
agent_label="$(keys_agent_label "$keys_agent")"
if [ "$value" = "none" ]; then
    keys_status "$window_uuid" "$agent_label gets no key in its box."
    exit 0
fi
label="$(keys_label_of "$keys_agent" "$value")"
kept="$(agentvm_secrets 2>/dev/null | /usr/bin/awk -F'\t' -v name="$value" '$1 == name { print "yes"; exit }')"
agentvm_last_error >/dev/null
if [ -z "$kept" ]; then
    keys_status "$window_uuid" "$agent_label gets $label in its box once its value is stored: select it above and paste it."
else
    keys_status "$window_uuid" "$agent_label gets $label in its box."
fi
