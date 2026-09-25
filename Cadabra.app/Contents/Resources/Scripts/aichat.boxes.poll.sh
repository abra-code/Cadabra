#!/bin/sh
# aichat.boxes.poll.sh
# Chained after anything that starts a job: repaints the jobs until none runs.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_poll "$window_uuid"
