#!/bin/sh
# aichat.boxes.box.shell.sh
# Shell: Terminal opens a shell in the box.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
agentvm_box_shell "$name"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not open a shell in $name" "$status"
fi
