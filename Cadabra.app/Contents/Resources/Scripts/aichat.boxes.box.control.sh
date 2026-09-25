#!/bin/sh
# aichat.boxes.box.control.sh
# View and Control: the box's screen, with keys and clicks reaching the box.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
agentvm_box_view "$name" interactive
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not show $name" "$status"
fi
