#!/bin/sh
# aichat.boxes.box.view.sh
# View: the box's supervisor shows its screen in a window; keys and clicks do not reach it.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

aichat_window_only
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
agentvm_box_view "$name"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not show $name" "$status"
fi
