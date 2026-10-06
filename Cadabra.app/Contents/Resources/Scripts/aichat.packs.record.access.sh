#!/bin/sh
# aichat.packs.record.access.sh
# The access of a row of the review table, clicked: a folder switches between reading and
# reading and changing. A single file, and a row no pack may hold, stay as they are.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.packs.record.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

row="${OMC_ACTIONUI_TRIGGER_CONTEXT:-}"
echo "row: $row"
case "$row" in
    ''|*[!0-9]*) exit 0 ;;
esac
state="$(record_state_file "$window_uuid")"
[ -f "$state" ] || exit 0
record_py access --state "$state" --row "$row"
record_show_rows "$window_uuid"
"$dialog" "$window_uuid" $record_table_view omc_select_row "$row"
