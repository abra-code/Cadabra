#!/bin/sh
# aichat.boxes.job.cancel.sh
# Cancel Job: agent-vm stops at its next safe point, so the job ends a moment later. An AgentVM
# install stops only before installing begins, and the question says so.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
job_id="$OMC_ACTIONUI_TABLE_400_COLUMN_4_VALUE"
[ -n "$job_id" ] || exit 0
title="$OMC_ACTIONUI_TABLE_400_COLUMN_1_VALUE"
kind="$(/usr/bin/awk -F'\t' -v id="$job_id" '$1 == id { print $2; exit }' "$(boxes_cache "$window_uuid" jobs)" 2>/dev/null)"
# An AgentVM install stops only before installing begins; that takes a few seconds, and
# stopping it halfway would leave a partial version behind.
text="agent-vm stops at the next safe point. A canceled image build leaves the image marked failed; delete it and build again."
if [ "$kind" = "agentvm-install" ]; then
    text="The download and the checks stop. Once installing has begun it takes a few seconds, and Cadabra lets it finish."
fi
"$alert" --level caution --title "Cancel \"$title\"?" --ok "Cancel Job" --cancel "Keep Running" "$text"
if [ $? -ne 0 ]; then
    exit 0
fi
agentvm_job_cancel "$job_id"
status=$?
if [ "$status" -ne 0 ]; then
    boxes_alert_error "Could not cancel the job" "$status"
fi
boxes_read_jobs "$window_uuid"
boxes_show_jobs "$window_uuid"
boxes_show_job "$window_uuid" "$job_id"
