#!/bin/sh
# aichat.box.network.init.sh
# The AgentVM Box Network window opens: takes the chat window's id from the request key into
# this window's own, and shows the box's connections.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
request="$("$pasteboard" "$BOXNET_REQUEST_KEY" get)"
"$pasteboard" "$BOXNET_REQUEST_KEY" set ""
"$pasteboard" "$(boxnet_context_key "$window_uuid")" set "$request"
boxnet_paint "$window_uuid"
