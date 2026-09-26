#!/bin/sh
# aichat.boxes.activated.sh
# The Box Manager became the active window again (WINDOW_DID_ACTIVATE_SUBCOMMAND_ID): repaints the
# jobs, and starts a poll loop for jobs another window started.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_activated "$window_uuid"
