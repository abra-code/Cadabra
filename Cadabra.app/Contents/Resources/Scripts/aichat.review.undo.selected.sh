#!/bin/sh
# aichat.review.undo.selected.sh
# Undo This Change...: the selected entry is put back as it was in the snapshot (review_undo).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

path="${OMC_ACTIONUI_TABLE_910_COLUMN_3_VALUE:-}"
covering="${OMC_ACTIONUI_TABLE_910_COLUMN_8_VALUE:-}"
# The button is disabled for an entry undone with its folder; checked again, as handlers can overlap.
if [ -z "$path" ] || { [ -n "$covering" ] && [ "$covering" != "-" ]; }; then
    exit 0
fi
review_undo "$OMC_ACTIONUI_WINDOW_UUID" "$path"
