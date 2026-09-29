#!/bin/sh
# aichat.boxes.agentvm.install.sh
# Install AgentVM... / Update AgentVM...: shown in the header when agent-vm is missing or too
# old. Asks, then downloads and installs the newest AgentVM release as a job the jobs table
# follows; the lists appear when it is done.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_install_agentvm "$window_uuid"
