#!/bin/sh
# aichat.boxes.images.update.all.sh
# Update All: every ready image whose guest daemon is out of date gets the one that comes with
# this agent-vm, in one job that updates them one after another.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_update_all "$window_uuid"
