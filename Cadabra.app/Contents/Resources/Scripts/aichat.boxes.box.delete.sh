#!/bin/sh
# aichat.boxes.box.delete.sh
# Delete: the box and its disk, after asking. agent-vm refuses a running box.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
"$alert" --level caution --title "Delete the box $name?" --ok "Delete" --cancel "Cancel" \
    "Its disk and everything installed or saved in it are deleted. The image it came from is kept."
if [ $? -ne 0 ]; then
    exit 0
fi
agentvm_box_delete "$name"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not delete $name" "$status"
    exit 0
fi
boxes_read_boxes "$window_uuid"
boxes_show_boxes "$window_uuid"
boxes_clear_detail "$window_uuid"
