#!/bin/sh
# aichat.packs.record.close.sh
# The Record a Pack window closes: a recording still running is stopped, and what was found
# and not saved is forgotten.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.packs.record.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

[ -n "$window_uuid" ] || exit 0
record_stop "$window_uuid"
record_forget "$window_uuid"
pb_set "aichatv2_packsrecord_parent_${window_uuid}" ""
pb_set "aichatv2_packsrecord_base_${window_uuid}" ""
