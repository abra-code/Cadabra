#!/bin/sh
# aichat.mcp.servers.packs.cancel.sh
# Cancel in the Choose Packs sheet: the sheet and its draft of ticks go; the stored packs and
# what is granted stay as they were.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

"$dialog" "$window_uuid" omc_window omc_dismiss_modal
mcp_packs_forget "$window_uuid"
