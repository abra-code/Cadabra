#!/bin/sh
# aichat.boxes.image.new.create.sh
# Build: checks the fields, starts the build as a job, hands the job to the Box Manager and
# closes the window. A refusal made before the job starts (ours, or the job store's) stays in
# the window under the fields; agent-vm's own refusals come from the running job, so the Box
# Manager shows them as a failed job.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_ni_create "$window_uuid"
status=$?
if [ "$status" -ne 0 ]; then
    exit 0
fi
boxes_manager_job_started "$boxes_ni_job"
boxes_ni_forget "$window_uuid"
"$dialog" "$window_uuid" omc_window omc_terminate_ok
