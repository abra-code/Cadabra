#!/bin/sh
# aichat.boxes.init.sh
# Opens the Box Manager: checks that agent-vm can be used, then lists the images, boxes and
# jobs. A poll loop starts when jobs are running (see aichat.boxes.library.sh).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
"$pasteboard" "$BOXES_MANAGER_KEY" set "$window_uuid"
# No poll loop runs for a window that just opened.
"$pasteboard" "$(boxes_key cadabra_boxes_poll "$window_uuid")" set ""
boxes_clear_detail "$window_uuid"
boxes_show_kind "$window_uuid" images
boxes_show_header "$window_uuid"
if [ $? -ne 0 ]; then
    exit 0
fi
boxes_populate "$window_uuid" images
running="$(boxes_running_count "$window_uuid")"
if [ "$running" -gt 0 ]; then
    "$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.boxes.poll"
fi
