#!/bin/sh
# aichat.boxes.image.selection.changed.sh
# An image row was (de)selected: its details and buttons.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_200_COLUMN_1_VALUE"
if [ -z "$name" ]; then
    boxes_clear_detail "$window_uuid"
    exit 0
fi
boxes_select_only "$window_uuid" "$BOXES_IMAGES_ID"
boxes_show_image "$window_uuid" "$name"
