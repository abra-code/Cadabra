#!/bin/sh
# aichat.mcp.servers.packs.record.sh
# Record a Pack... in the Choose Packs sheet: the sheet goes, as with Cancel, and the Record a
# Pack window opens. That window refreshes this one after it saved a pack. The packs ticked in
# the sheet at this moment go with it, as what the recording can start with; they are not
# stored as the chosen packs.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.packs.record.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

base="$(mcp_packs_view chosen --list "$(mcp_packs_list_file "$window_uuid")" \
    --ticked "$(mcp_packs_ticked_file "$window_uuid")" 2>/dev/null | /usr/bin/tr '\n' ',')"
pb_set "$RECORD_BASE_KEY" "${base%,}"
"$dialog" "$window_uuid" omc_window omc_dismiss_modal
mcp_packs_forget "$window_uuid"
pb_set "$RECORD_PARENT_KEY" "$window_uuid"
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.packs.record"
