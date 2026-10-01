#!/bin/sh
# aichat.mcp.servers.info.done.sh
# Done on an information sheet of Agentic Session Tools (mcp_info_sheet): the sheet goes, and its
# file with it.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"

echo "[$(/usr/bin/basename "$0")]"

"$dialog" "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_dismiss_modal
/bin/rm -f "$(mcp_info_sheet_file "$OMC_ACTIONUI_WINDOW_UUID")"
