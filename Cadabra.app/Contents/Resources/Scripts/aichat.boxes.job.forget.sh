#!/bin/sh
# aichat.boxes.job.forget.sh
# Remove: a finished job leaves the list (and its folder under Jobs).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
job_id="$OMC_ACTIONUI_TABLE_400_COLUMN_4_VALUE"
[ -n "$job_id" ] || exit 0
agentvm_job_forget "$job_id"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not remove the job" "$status"
fi
boxes_read_jobs "$window_uuid"
boxes_show_jobs "$window_uuid"
boxes_clear_detail "$window_uuid"
