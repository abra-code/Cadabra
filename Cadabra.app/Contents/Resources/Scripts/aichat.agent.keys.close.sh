#!/bin/sh
# aichat.agent.keys.close.sh
# The window closed: its context is forgotten.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agent.keys.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
"$pasteboard" "$(keys_context_key "$window_uuid")" set ""
