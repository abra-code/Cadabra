#!/bin/sh
# aichat.packs.record.init.sh
# The Record a Pack window opens: the folder to run in starts as the Project folder, and the
# window takes over the Agentic Session Tools window that opened it, to refresh it after a save.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.packs.record.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

mcp_prefs_init_if_missing
"$dialog" "$window_uuid" $record_folder_view "$(mcp_prefs_get_string servers/local/project)"
pb_set "aichatv2_packsrecord_parent_${window_uuid}" "$(pb_get "$RECORD_PARENT_KEY")"
pb_set "$RECORD_PARENT_KEY" ""
record_forget "$window_uuid"
