#!/bin/sh
# aichat.mcp.servers.readonly.changed.sh
# Read-only project changed (the agent panel's 502, or the tools box pane's 528): no snapshot is
# taken of a project shared read-only, so Snapshot the project first follows it
# (mcp_snapshot_apply). Nothing is stored here; Start stores both.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
# Which toggle the user sees: the agent panel's for an agent in a box without Cadabra's tools,
# else the box pane's.
read_only="${OMC_ACTIONUI_VIEW_528_VALUE:-false}"
box_agent="$(pb_get "aichatv2_toolsbox_${window_uuid}")"
box_pane="$(pb_get "aichatv2_toolsboxpane_${window_uuid}")"
if [ -n "$box_agent" ] && [ "$box_pane" != "yes" ]; then
    read_only="${OMC_ACTIONUI_VIEW_502_VALUE:-false}"
fi
mcp_snapshot_apply "$window_uuid" box "$read_only"
