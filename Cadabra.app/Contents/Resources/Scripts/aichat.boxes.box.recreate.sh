#!/bin/sh
# aichat.boxes.box.recreate.sh
# Recreate: the stopped kept box made again from its image as the image is now, after asking. For
# use after its image was updated (a newer agent-vm-guest, say), or when agent-vm asks for
# it. The name, CPUs, memory and network rules stay, so an agent set to run in the box still
# finds it; what was saved in the box goes. agent-vm refuses a running box.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
image="$OMC_ACTIONUI_TABLE_300_COLUMN_3_VALUE"
[ -n "$name" ] || exit 0
from="its image"
[ -n "$image" ] && [ "$image" != "-" ] && from="the image $image"
"$alert" --level caution --title "Recreate the box $name?" --ok "Recreate" --cancel "Cancel" \
    "It is made again from $from as the image is now, with the same name, CPUs, memory and network rules. Everything installed or saved in the box, logins included, is deleted."
if [ $? -ne 0 ]; then
    exit 0
fi
agentvm_box_recreate "$name"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not recreate $name" "$status"
fi
# Read again after a failure too: agent-vm can delete the box and then fail to make it again
# (its message gives the command that does), and the list must not show a box that is gone.
boxes_read_boxes "$window_uuid"
boxes_show_boxes "$window_uuid"
boxes_show_box "$window_uuid" "$name"
