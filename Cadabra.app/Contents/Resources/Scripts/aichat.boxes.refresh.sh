#!/bin/sh
# aichat.boxes.refresh.sh
# The refresh button: reads everything again, images included.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_show_header "$window_uuid"
if [ $? -ne 0 ]; then
    exit 0
fi
boxes_populate "$window_uuid" images
boxes_show_selected "$window_uuid"
running="$(boxes_running_count "$window_uuid")"
if [ "$running" -gt 0 ]; then
    "$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.boxes.poll"
fi
