#!/bin/sh
# aichat.mcp.servers.packs.toggle.sh
# A checkbox in the Choose Packs sheet: the pack in that row is ticked or unticked in the sheet's
# draft, and shown in the preview. The row (0-based) is the trigger context of the table's button
# column. A pack that cannot be used on this Mac stays unticked; its preview says why.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

row="${OMC_ACTIONUI_TRIGGER_CONTEXT:-}"
echo "row: $row"
case "$row" in
    ''|*[!0-9]*) exit 0 ;;
esac

pack_id="$(mcp_packs_view toggle --list "$(mcp_packs_list_file "$window_uuid")" \
    --ticked "$(mcp_packs_ticked_file "$window_uuid")" --row "$row")"
[ -z "$pack_id" ] && exit 0
mcp_packs_show "$window_uuid" "$row" "$pack_id"
