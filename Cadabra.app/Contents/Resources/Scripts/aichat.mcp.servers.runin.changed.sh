#!/bin/sh
# aichat.mcp.servers.runin.changed.sh
# The Where tools run picker changed: the sandbox paths or the tools box panel follow it
# (mcp_tools_apply_run_in). Nothing is stored here; Start stores the choice.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"

echo "[$(/usr/bin/basename "$0")]"

mcp_tools_apply_run_in "$OMC_ACTIONUI_WINDOW_UUID" "${OMC_ACTIONUI_VIEW_292_VALUE:-mac}"
