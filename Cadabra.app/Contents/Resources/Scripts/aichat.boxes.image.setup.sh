#!/bin/sh
# aichat.boxes.image.setup.sh
# Full Disk Access...: explains the steps, then opens the image in a window as a job. The job
# ends when the user closes that window.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_200_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
"$alert" --level note --title "Give agent-vm-guest Full Disk Access in $name" --ok "Open $name" --cancel "Cancel" \
    "The image opens in a window. There: open System Settings > Privacy & Security > Full Disk Access, drag agent-vm-guest into the list (it is in /usr/local/libexec), turn it on, and enter the password if asked (the window's Type Password button types it). Then close the window; the job ends with it."
if [ $? -ne 0 ]; then
    exit 0
fi
job_id="$(agentvm_image_setup_job "$name")"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not open $name" "$status"
    exit 0
fi
boxes_after_job_start "$window_uuid" "$job_id"
