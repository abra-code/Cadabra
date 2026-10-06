#!/bin/sh
# aichat.packs.record.stop.sh
# Stop: ends the window's recording. The Record handler, still running, then says so and puts
# the controls back.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.packs.record.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

record_stop "$window_uuid"
