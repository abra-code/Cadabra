#!/bin/sh
# aichat.review.selection.changed.sh
# A change was selected, or the selection cleared: the detail pane follows (review_detail).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

review_detail "$OMC_ACTIONUI_WINDOW_UUID" "${OMC_ACTIONUI_TABLE_910_COLUMN_0_VALUE:-}"
