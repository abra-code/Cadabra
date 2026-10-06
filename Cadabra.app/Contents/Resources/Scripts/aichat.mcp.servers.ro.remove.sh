#!/bin/sh
# aichat.mcp.servers.ro.remove.sh
# Removes the selected row from the additional read-only list. A row only a sandbox pack grants
# (kind "pack", the hidden third column: mcp_refresh_granted) is not the user's to remove here.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
RO_REMOVE_BTN_ID=332

selected="$OMC_ACTIONUI_TABLE_330_COLUMN_1_VALUE"
[ -z "$selected" ] && exit 0
[ "${OMC_ACTIONUI_TABLE_330_COLUMN_3_VALUE:-}" = "pack" ] && exit 0

mcp_prefs_array_remove_value servers/local/allowed-read "$selected"
mcp_refresh_granted "$window_uuid"
"$dialog" "$window_uuid" $RO_REMOVE_BTN_ID omc_disable
