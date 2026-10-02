#!/bin/sh
# aichat.boxes.box.stop.sh
# Stop: a clean shutdown of the guest, as an agent-vm job. Programs running in the box end with
# it, so a box with programs in it is asked about first.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

aichat_window_only
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
[ -n "$name" ] || exit 0
row="$(boxes_row "$window_uuid" "$name")"
programs="$(boxes_field "$row" 5)"
case "$programs" in
    ''|0) ;;
    *)
        "$alert" --level caution --title "Stop $name?" --ok "Stop" --cancel "Cancel" \
            "Programs running in the box right now: $programs, from Cadabra or elsewhere (a Terminal shell, another app). Stopping the box ends them."
        if [ $? -ne 0 ]; then
            exit 0
        fi ;;
esac
job_id="$(agentvm_box_stop_job "$name")"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not stop $name" "$status"
    exit 0
fi
boxes_after_job_start "$window_uuid" "$job_id"
