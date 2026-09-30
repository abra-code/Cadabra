#!/bin/sh
# aichat.box.network.saved.selection.changed.sh
# A host saved for the agent is selected: Remove... is offered.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
if [ -n "$OMC_ACTIONUI_TABLE_808_COLUMN_1_VALUE" ]; then
    "$dialog" "$window_uuid" "$BOXNET_SAVED_REMOVE_ID" omc_enable
else
    "$dialog" "$window_uuid" "$BOXNET_SAVED_REMOVE_ID" omc_disable
fi
