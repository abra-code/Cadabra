#!/bin/sh
# aichat.boxes.box.new.cancel.sh
# Cancel: closes the New Box window without creating anything.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
"$pasteboard" "$(boxes_key cadabra_boxes_new_images "$window_uuid")" set ""
"$dialog" "$window_uuid" omc_window omc_terminate_cancel
