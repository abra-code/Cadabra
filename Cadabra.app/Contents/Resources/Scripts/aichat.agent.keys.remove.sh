#!/bin/sh
# aichat.agent.keys.remove.sh
# Remove...: the selected key leaves the login Keychain, after a confirmation, since every agent
# that uses the same variable loses it. This agent then gets no key.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agent.keys.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
keys_context "$window_uuid" || exit 0
name="$OMC_ACTIONUI_TABLE_701_COLUMN_2_VALUE"
if [ -z "$name" ] || ! keys_is_agent_key "$keys_agent" "$name"; then
    exit 0
fi
label="$(keys_label_of "$keys_agent" "$name")"
"$alert" --level caution --title "Remove $label from the Keychain?" --ok "Remove" --cancel "Cancel" \
    "Every agent that uses $name loses it. To use it again, store its value again."
answer=$?
if [ "$answer" -ne 0 ]; then
    exit 0
fi
agentvm_secret_delete "$name"
status=$?
if [ "$status" -ne 0 ]; then
    keys_status "$window_uuid" "Could not remove $label: $(agentvm_last_error "$status")"
    exit 0
fi
note=""
if [ "$(acp_agent_secret "$keys_agent")" = "$name" ]; then
    acp_agent_set_secret "$keys_agent" none
    set_status=$?
    if [ "$set_status" -ne 0 ]; then
        note=" Cadabra's settings could not be written, so the agent still asks for it."
    fi
fi
keys_paint "$window_uuid"
keys_status "$window_uuid" "Removed $label from the Keychain.$note"
