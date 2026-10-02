#!/bin/sh
# aichat.boxes.agentvm.open.sh
# Open AgentVM: the AgentVM app, at the selected box when one is selected. Everything about a
# box that this window does not do is done there.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

aichat_window_only
name="$OMC_ACTIONUI_TABLE_300_COLUMN_1_VALUE"
if [ -n "$name" ] && agentvm_valid_name "$name"; then
    agentvm_app_show "$name"
    exit 0
fi
agentvm_app_show
