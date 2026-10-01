#!/bin/sh
# aichat.mcp.servers.runin.changed.sh
# The Where tools run picker changed: the sandbox paths or the tools box panel follow it
# (mcp_tools_apply_run_in), and Snapshot the project first shows that place's setting
# (mcp_snapshot_apply). Nothing is stored here; Start stores the choice.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"

echo "[$(/usr/bin/basename "$0")]"

mcp_tools_apply_run_in "$OMC_ACTIONUI_WINDOW_UUID" "${OMC_ACTIONUI_VIEW_292_VALUE:-mac}"
run_in="${OMC_ACTIONUI_VIEW_292_VALUE:-mac}"
mcp_snapshot_apply "$OMC_ACTIONUI_WINDOW_UUID" "$(mcp_snapshot_place "$run_in")" "${OMC_ACTIONUI_VIEW_528_VALUE:-false}" show
