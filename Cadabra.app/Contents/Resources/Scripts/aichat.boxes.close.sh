#!/bin/sh
# aichat.boxes.close.sh
# The AgentVM Boxes window closed (END_CANCEL_SUBCOMMAND_ID). Boxes and jobs go on without it;
# the poll loop stops, and the window's cache files and pasteboard keys go.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
[ -n "$window_uuid" ] || exit 0
"$pasteboard" "$(boxes_key cadabra_boxes_poll "$window_uuid")" set "closed"
"$pasteboard" "$(boxes_key cadabra_boxes_selected "$window_uuid")" set ""
"$pasteboard" "$(boxes_key cadabra_boxes_watch "$window_uuid")" set ""
open_window="$("$pasteboard" "$BOXES_WINDOW_KEY" get)"
if [ "$open_window" = "$window_uuid" ]; then
    "$pasteboard" "$BOXES_WINDOW_KEY" set ""
fi
for kind in boxes jobs vms cards problem; do
    /bin/rm -f "$(boxes_cache "$window_uuid" "$kind")"
done
