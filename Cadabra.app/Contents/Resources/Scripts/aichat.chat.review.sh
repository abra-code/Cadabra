#!/bin/sh
# aichat.chat.review.sh
# Changes... on a chat window's line: opens Review Changes on the window's project snapshot.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

id="$(snapshot_window_session "$OMC_ACTIONUI_WINDOW_UUID")"
review_request "$id"
status=$?
if [ "$status" -ne 0 ]; then
    exit 0
fi
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.review"
