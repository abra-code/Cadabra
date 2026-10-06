#!/bin/sh
# aichat.packs.record.keep.sh
# A checkbox of the review table: the folder in that row (0-based, the trigger context of the
# table's button column) is kept in the pack or left out. A row no pack may hold stays unticked.

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
record_py keep --state "$state" --row "$row"
record_show_rows "$window_uuid"
"$dialog" "$window_uuid" $record_table_view omc_select_row "$row"
