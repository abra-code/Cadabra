#!/bin/sh
# aichat.boxes.job.selection.changed.sh
# A job row was (de)selected. Its id is the hidden fourth column.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
job_id="$OMC_ACTIONUI_TABLE_400_COLUMN_4_VALUE"
if [ -z "$job_id" ]; then
    boxes_clear_detail "$window_uuid"
    exit 0
fi
boxes_select_only "$window_uuid" "$BOXES_JOBS_ID"
boxes_show_job "$window_uuid" "$job_id"
