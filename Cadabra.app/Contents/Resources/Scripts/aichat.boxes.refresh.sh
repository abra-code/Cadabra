#!/bin/sh
# aichat.boxes.refresh.sh
# The refresh button: reads the boxes again now.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

aichat_window_only
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_refresh "$window_uuid"
boxes_ensure_poll "$window_uuid"
