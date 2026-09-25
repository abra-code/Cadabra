#!/bin/sh
# aichat.boxes.kind.changed.sh
# The Images/Boxes picker: its value is the 1-based option index.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
case "$OMC_ACTIONUI_VIEW_110_VALUE" in
    2) boxes_show_kind "$window_uuid" boxes ;;
    *) boxes_show_kind "$window_uuid" images ;;
esac
boxes_select_only "$window_uuid"
boxes_clear_detail "$window_uuid"
