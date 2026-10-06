#!/bin/sh
# aichat.mcp.servers.packs.selection.changed.sh
# A row picked in the Choose Packs sheet: the preview shows what that pack holds. The pack's id
# is the table's hidden third column.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

pack_id="${OMC_ACTIONUI_TABLE_600_COLUMN_3_VALUE:-}"
[ -z "$pack_id" ] && exit 0
"$dialog" "$window_uuid" $mcp_packs_preview_view \
    "$(mcp_packs_view preview --list "$(mcp_packs_list_file "$window_uuid")" --id="$pack_id")"
