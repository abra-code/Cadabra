#!/bin/sh
# aichat.review.close.sh
# The window closes (Done, Keep Changes or the close button): its session key and file go.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

review_forget "$OMC_ACTIONUI_WINDOW_UUID"
