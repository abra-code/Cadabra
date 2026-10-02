#!/bin/sh
# aichat.boxes.poll.sh
# The AgentVM Boxes window's poll loop (boxes_poll), chained by the handlers that open, activate
# and refresh it. Runs until the window closes, a newer loop takes over, or Cadabra quits.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
[ -n "$window_uuid" ] || exit 0
boxes_poll "$window_uuid"
