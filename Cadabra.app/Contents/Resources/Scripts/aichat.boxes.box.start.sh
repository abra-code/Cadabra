#!/bin/sh
# aichat.boxes.box.start.sh
# Start: a job, since a box takes 10 to 30 seconds to be ready. Cadabra owns the box it starts,
# so it stops when Cadabra exits.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
job_id="$(agentvm_box_start_job "$name")"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not start $name" "$status"
    exit 0
fi
boxes_after_job_start "$window_uuid" "$job_id"
