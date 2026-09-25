#!/bin/sh
# aichat.boxes.image.new.box.sh
# New Box... of an image: the New Box window, with this image chosen.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_200_COLUMN_1_VALUE"
"$pasteboard" "$BOXES_NEW_IMAGE_KEY" set "$name"
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.boxes.box.new"
