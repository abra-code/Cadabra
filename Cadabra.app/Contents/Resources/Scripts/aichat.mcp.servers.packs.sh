#!/bin/sh
# aichat.mcp.servers.packs.sh
# Choose Packs... in Agentic Session Tools: a sheet listing every sandbox pack with a checkbox,
# beside a preview of what the selected pack holds. The ticks are a draft until Use These Packs
# (aichat.mcp.servers.packs.use.sh); nothing in the sheet changes what is granted before that.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

mcp_prefs_init_if_missing

list="$(mcp_packs_list_file "$window_uuid")"
mcp_packs_view open --prefs "$mcp_prefs" --bundle "$OMC_APP_BUNDLE_PATH" \
    --list "$list" --ticked "$(mcp_packs_ticked_file "$window_uuid")"
status=$?
if [ "$status" -ne 0 ]; then
    mcp_packs_forget "$window_uuid"
    "$alert" --level "stop" --title "$APPLET_NAME" --ok "OK" \
        "The sandbox packs could not be listed. Check that ~/Library/Application Support/Cadabra is writable."
    exit 0
fi

"$dialog" "$window_uuid" omc_window omc_present_modal "aichat.mcp.servers.packs"
# The first pack is selected, so the preview is never empty.
first="$(/usr/bin/jq -r '.[0].id // empty' "$list" 2>/dev/null)"
mcp_packs_show "$window_uuid" 0 "$first"
