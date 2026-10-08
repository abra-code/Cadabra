#!/bin/sh
# aichat.boxes.box.start.sh
# Start: an agent-vm job, since a box takes 10 to 30 seconds to be ready. Cadabra owns the box
# it starts, so it stops when Cadabra exits.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

aichat_window_only
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
# The box's system, from the reading the list shows: a Linux box needs no virtual machine slot.
guest="$(/usr/bin/awk -F'\t' -v name="$name" '$1 == name { print $9; exit }' "$(boxes_cache "$window_uuid" boxes)" 2>/dev/null)"
job_id="$(agentvm_box_start_job "$name" "$guest")"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not start $name" "$status"
    exit 0
fi
boxes_after_job_start "$window_uuid" "$job_id"
