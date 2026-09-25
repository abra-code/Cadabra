#!/bin/sh
# aichat.boxes.image.update.guest.sh
# Update Guest: installs the agent-vm-guest beside Cadabra's agent-vm into the image, as a job.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_200_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
job_id="$(agentvm_image_update_guest_job "$name")"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not update the guest in $name" "$status"
    exit 0
fi
boxes_after_job_start "$window_uuid" "$job_id"
