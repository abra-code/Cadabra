#!/bin/sh
# aichat.boxes.image.new.from.sh
# New Image from This... of an image: the New Image window, starting from this image.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
"$pasteboard" "$BOXES_NI_BASE_KEY" set "$OMC_ACTIONUI_TABLE_200_COLUMN_1_VALUE"
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.boxes.image.new"
