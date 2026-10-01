#!/bin/sh
# aichat.review.init.sh
# The Review Changes window opens: takes the session from the request key into its own, and shows
# what the session changed (review_paint).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
review_take_request "$window_uuid"
review_paint "$window_uuid"
