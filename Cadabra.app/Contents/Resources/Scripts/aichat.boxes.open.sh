#!/bin/sh
# aichat.boxes.open.sh
# Tools > AgentVM: brings the open Box Manager (the AgentVM window) to the front, or opens
# one. There is one Box Manager, so the windows that change what it lists have one to refresh.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

manager="$("$pasteboard" "$BOXES_MANAGER_KEY" get)"
if [ -n "$manager" ]; then
    "$dialog" "$manager" omc_window omc_select
    exit 0
fi
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.boxes"
