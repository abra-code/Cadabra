#!/bin/sh
# aichat.boxes.init.sh
# Opens the AgentVM Boxes window: shows the boxes and their states, and starts the poll loop that
# keeps them current (see aichat.boxes.library.sh).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
[ -n "$window_uuid" ] || exit 0
"$pasteboard" "$BOXES_WINDOW_KEY" set "$window_uuid"
# No poll loop runs for a window that just opened, nothing is selected, and nothing is painted.
"$pasteboard" "$(boxes_key cadabra_boxes_poll "$window_uuid")" set ""
"$pasteboard" "$(boxes_key cadabra_boxes_selected "$window_uuid")" set ""
"$pasteboard" "$(boxes_key cadabra_boxes_watch "$window_uuid")" set ""
/bin/rm -f "$(boxes_cache "$window_uuid" cards)"
boxes_refresh "$window_uuid"
boxes_ensure_poll "$window_uuid"
