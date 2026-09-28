#!/bin/sh
# aichat.chat.box.network.sh
# Network... on a chat window's box line: opens the AgentVM Box Network window for this window's
# box. The chat window's id is handed over in BOXNET_REQUEST_KEY; the window reads the box from
# this window's box line stamp.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

win="$OMC_ACTIONUI_WINDOW_UUID"
stamp="$(pb_get "aichatv2_boxline_${win}")"
if [ -z "$stamp" ]; then
    exit 0
fi
"$pasteboard" "$BOXNET_REQUEST_KEY" set "$win"
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.box.network"
