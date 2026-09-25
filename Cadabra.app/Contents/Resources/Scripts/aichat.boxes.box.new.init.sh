#!/bin/sh
# aichat.boxes.box.new.init.sh
# Fills the New Box window: the ready images (the one New Box... was pressed on chosen), the
# network packs agent-vm knows, and the defaults.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_new_init "$window_uuid"
