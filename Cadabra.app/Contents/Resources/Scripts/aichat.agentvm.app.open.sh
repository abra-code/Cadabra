#!/bin/sh
# aichat.agentvm.app.open.sh
# Set Up AgentVM...: the button a "runs in" row shows while there is no box to choose (Select ACP
# Agent, Agentic Session Tools). Opens the AgentVM app, which installs agent-vm and makes images
# and boxes; when the app is not on this Mac, an alert offers its download page. What it makes
# shows the next time the window that held the button opens.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh"

echo "[$(/usr/bin/basename "$0")]"

aichat_window_only
agentvm_app_show
