#!/bin/sh
# aichat.agent.keys.store.sh
# Store: the value goes into the login Keychain through agent-vm, on stdin only, and the key
# becomes the one the agent gets. The field is cleared first thing, since OMC hands its value to
# every handler of this window while it holds one. Only the button stores: the field has no
# actionID, since ActionUI fires a SecureField's actionID on focus loss too, which would store a
# value the user did not ask to store, twice with the button, or under a row clicked meanwhile.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agent.keys.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
"$dialog" "$window_uuid" "$KEYS_VALUE_ID" ""
keys_context "$window_uuid" || exit 0
name="$OMC_ACTIONUI_TABLE_701_COLUMN_2_VALUE"
if [ -z "$name" ] || ! keys_is_agent_key "$keys_agent" "$name"; then
    keys_status "$window_uuid" "Select a key first."
    exit 0
fi
label="$(keys_label_of "$keys_agent" "$name")"
value="$(keys_trim "$keys_pasted_value")"
keys_pasted_value=""
if [ -z "$value" ]; then
    keys_status "$window_uuid" "Paste the value of $label first."
    exit 0
fi
keys_status "$window_uuid" "Storing $label..."
printf '%s' "$value" | agentvm_secret_set "$name"
status=$?
value=""
if [ "$status" -ne 0 ]; then
    keys_status "$window_uuid" "Could not store $label: $(agentvm_last_error "$status")"
    exit 0
fi
acp_agent_set_secret "$keys_agent" "$name"
set_status=$?
keys_paint "$window_uuid"
agent_label="$(keys_agent_label "$keys_agent")"
if [ "$set_status" -ne 0 ]; then
    keys_status "$window_uuid" "Stored $label in the Keychain, but Cadabra's settings could not be written, so $agent_label does not get it yet."
    exit 0
fi
keys_status "$window_uuid" "Stored $label. $agent_label gets it in its box."
