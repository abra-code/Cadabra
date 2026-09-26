#!/bin/sh
# aichat.boxes.image.new.init.sh
# Fills the New Image window: the ready images to start from and the recipes Cadabra ships.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_ni_init "$window_uuid"
