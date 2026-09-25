#!/bin/sh
# aichat.boxes.close.sh
# The Box Manager closed (END_CANCEL_SUBCOMMAND_ID). Jobs go on without it; the poll loop stops,
# and the window's cache files and pasteboard keys go.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
"$pasteboard" "$(boxes_key cadabra_boxes_poll "$window_uuid")" set "closed"
"$pasteboard" "$(boxes_key cadabra_boxes_selected "$window_uuid")" set ""
"$pasteboard" "$(boxes_key cadabra_boxes_watch "$window_uuid")" set ""
"$pasteboard" "$(boxes_key cadabra_boxes_seen "$window_uuid")" set ""
manager="$("$pasteboard" "$BOXES_MANAGER_KEY" get)"
if [ "$manager" = "$window_uuid" ]; then
    "$pasteboard" "$BOXES_MANAGER_KEY" set ""
fi
/bin/rm -f "$(boxes_cache "$window_uuid" images)" "$(boxes_cache "$window_uuid" boxes)" "$(boxes_cache "$window_uuid" jobs)"
