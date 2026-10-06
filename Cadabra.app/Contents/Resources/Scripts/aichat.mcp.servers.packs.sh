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

mcp_packs_sheet_open "$window_uuid"
