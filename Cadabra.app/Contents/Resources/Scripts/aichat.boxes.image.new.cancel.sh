#!/bin/sh
# aichat.boxes.image.new.cancel.sh
# Cancel: closes the New Image window without building anything.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_ni_forget "$window_uuid"
"$dialog" "$window_uuid" omc_window omc_terminate_cancel
