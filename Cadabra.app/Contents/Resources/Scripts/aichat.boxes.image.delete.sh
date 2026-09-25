#!/bin/sh
# aichat.boxes.image.delete.sh
# Delete: the image, after asking. agent-vm refuses an image that boxes or images come from.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_200_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
"$alert" --level caution --title "Delete the image $name?" --ok "Delete" --cancel "Cancel" \
    "Its disk is deleted. Building it again takes minutes, or longer for an image with Xcode."
if [ $? -ne 0 ]; then
    exit 0
fi
agentvm_image_delete "$name"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not delete $name" "$status"
    exit 0
fi
boxes_read_images "$window_uuid"
boxes_show_images "$window_uuid"
boxes_clear_detail "$window_uuid"
