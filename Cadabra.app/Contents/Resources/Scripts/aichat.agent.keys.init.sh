#!/bin/sh
# aichat.agent.keys.init.sh
# Fills the Keys window for the agent Select ACP Agent's Keys... was pressed for.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agent.keys.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
request="$("$pasteboard" "$KEYS_REQUEST_KEY" get)"
"$pasteboard" "$KEYS_REQUEST_KEY" set ""
if [ -z "$request" ]; then
    keys_status "$window_uuid" "Open this window with Keys... in Select ACP Agent."
    "$dialog" "$window_uuid" "$KEYS_USE_ID" omc_disable
    exit 0
fi
"$pasteboard" "$(keys_context_key "$window_uuid")" set "$request"
keys_paint "$window_uuid"
keys_paint_login "$window_uuid"
