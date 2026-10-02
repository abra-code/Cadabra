#!/bin/sh
# aichat.boxes.box.selection.changed.sh
# A box was selected or deselected in the list: the buttons follow.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

aichat_window_only
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
if [ -n "$name" ] && agentvm_valid_name "$name"; then
    "$pasteboard" "$(boxes_key cadabra_boxes_selected "$window_uuid")" set "$name"
else
    "$pasteboard" "$(boxes_key cadabra_boxes_selected "$window_uuid")" set ""
fi
boxes_paint_buttons "$window_uuid"
