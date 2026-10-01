#!/bin/sh
# aichat.review.refresh.sh
# Refresh: what the project changed is read again (review_paint).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

review_paint "$OMC_ACTIONUI_WINDOW_UUID"
