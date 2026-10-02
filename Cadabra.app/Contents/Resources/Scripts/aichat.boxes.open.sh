#!/bin/sh
# aichat.boxes.open.sh
# Tools > AgentVM Boxes: brings the open AgentVM Boxes window to the front, or opens one. On a
# macOS older than boxes need, it says so and opens nothing: there would be nothing to show.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

reason="$(agentvm_macos_reason "$(/usr/bin/sw_vers -productVersion 2>/dev/null)")"
if [ -n "$reason" ]; then
    "$alert" --level caution --title "AgentVM boxes cannot be used on this Mac" --ok "OK" "$reason"
    exit 0
fi
open_window="$("$pasteboard" "$BOXES_WINDOW_KEY" get)"
if [ -n "$open_window" ]; then
    "$dialog" "$open_window" omc_window omc_select
    exit 0
fi
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.boxes"
