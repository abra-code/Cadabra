#!/bin/sh
# aichat.boxes.reveal.sh
# The folder button of an image or a box: shows its folder in the Finder.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
selected="$("$pasteboard" "$(boxes_key cadabra_boxes_selected "$window_uuid")" get)"
case "$selected" in
    image:*) path="$(boxes_field "$(boxes_row "$(boxes_cache "$window_uuid" images)" "${selected#image:}")" 14)" ;;
    box:*)   path="$(boxes_field "$(boxes_row "$(boxes_cache "$window_uuid" boxes)" "${selected#box:}")" 16)" ;;
    *)       exit 0 ;;
esac
[ -n "$path" ] && [ -d "$path" ] || exit 0
"$boxes_open" -R "$path"
