#!/bin/sh
# aichat.review.reveal.sh
# Show in Finder: the selected entry, or the project folder.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

review_reveal "$OMC_ACTIONUI_WINDOW_UUID" "${OMC_ACTIONUI_TABLE_910_COLUMN_3_VALUE:-}"
