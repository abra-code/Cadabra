#!/bin/sh
# aichat.boxes.box.new.create.sh
# Create: checks the fields, creates the box (a second or two), refreshes the Box Manager and
# closes the window. A refusal, ours or agent-vm's, stays in the window under the fields.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_new_create "$window_uuid"
status=$?
if [ "$status" -ne 0 ]; then
    exit 0
fi
boxes_refresh_manager
"$pasteboard" "$(boxes_key cadabra_boxes_new_images "$window_uuid")" set ""
"$dialog" "$window_uuid" omc_window omc_terminate_ok
