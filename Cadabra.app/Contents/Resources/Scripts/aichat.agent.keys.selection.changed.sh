#!/bin/sh
# aichat.agent.keys.selection.changed.sh
# A key was selected: its value can be stored, a stored one removed, and the catalog says how to
# get it.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agent.keys.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
keys_context "$window_uuid" || exit 0
name="$OMC_ACTIONUI_TABLE_701_COLUMN_2_VALUE"
state="$OMC_ACTIONUI_TABLE_701_COLUMN_3_VALUE"
if [ -z "$name" ] || ! keys_is_agent_key "$keys_agent" "$name"; then
    "$dialog" "$window_uuid" "$KEYS_VALUE_ID" omc_disable
    "$dialog" "$window_uuid" "$KEYS_HINT_ID" ""
    "$dialog" "$window_uuid" "$KEYS_STORE_ID" omc_disable
    "$dialog" "$window_uuid" "$KEYS_REMOVE_ID" omc_disable
    exit 0
fi
"$dialog" "$window_uuid" "$KEYS_HINT_ID" "$(keys_hint_of "$keys_agent" "$name")"
"$dialog" "$window_uuid" "$KEYS_VALUE_ID" omc_enable
"$dialog" "$window_uuid" "$KEYS_STORE_ID" omc_enable
case "$state" in
    Stored*) "$dialog" "$window_uuid" "$KEYS_REMOVE_ID" omc_enable ;;
    *)       "$dialog" "$window_uuid" "$KEYS_REMOVE_ID" omc_disable ;;
esac
