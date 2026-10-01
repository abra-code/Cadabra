#!/bin/sh
# aichat.review.keep.sh
# Keep Changes...: the snapshot is deleted after the user confirms, and the window closes.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

review_keep "$OMC_ACTIONUI_WINDOW_UUID"
status=$?
if [ "$status" -eq 0 ]; then
    "$dialog" "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok
fi
