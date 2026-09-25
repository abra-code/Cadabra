#!/bin/sh
# aichat.boxes.box.selection.changed.sh
# A box row was (de)selected: its details, recent programs, refused hosts and buttons.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
if [ -z "$name" ]; then
    boxes_clear_detail "$window_uuid"
    exit 0
fi
boxes_select_only "$window_uuid" "$BOXES_BOXES_ID"
boxes_show_box "$window_uuid" "$name"
