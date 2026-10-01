#!/bin/sh
# aichat.review.undo.all.sh
# Undo All...: every change is put back as it was in the snapshot (review_undo).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

review_undo "$OMC_ACTIONUI_WINDOW_UUID"
