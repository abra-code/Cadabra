#!/bin/sh
# aichat.boxes.image.new.source.changed.sh
# Start from: a restore image (1) or an existing image (2); the picker delivers its index.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
case "$OMC_ACTIONUI_VIEW_701_VALUE" in
    2) boxes_ni_source "$window_uuid" 2 ;;
    *) boxes_ni_source "$window_uuid" 1 ;;
esac
