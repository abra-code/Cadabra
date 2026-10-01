#!/bin/sh
# aichat.mcp.servers.box.network.sh
# Network Rules... in the tools box pane: a sheet saying which hosts programs in the box may reach
# (mcp_tools_box_network_text). The box is the agent's, for a launch that runs an agent in a box,
# else the one chosen under Where tools run.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.acp.agents.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
box_agent="$(pb_get "aichatv2_toolsbox_${window_uuid}")"
if [ -n "$box_agent" ]; then
    run_in="$(acp_agent_run_in "$box_agent")"
else
    run_in="${OMC_ACTIONUI_VIEW_292_VALUE:-}"
fi
case "$run_in" in
    box:?*) title="Network of the AgentVM box ${run_in#box:}" ;;
    new:?*) title="Network of a new AgentVM box from ${run_in#new:}" ;;
    *)      title="Network of the AgentVM box" ;;
esac
text="$(mcp_tools_box_network_text "$window_uuid" "$run_in" "$box_agent")"
if [ -z "$text" ]; then
    text="The box's network rules cannot be read right now. **Tools > AgentVM** shows them."
fi
# The last paragraph names Tools > AgentVM, Cadabra's own window for boxes: reword it when editing
# boxes moves out of Cadabra to the AgentVM app.
mcp_info_sheet "$window_uuid" "## $title

$text

Rules are changed in **Tools > AgentVM**. A host a program was refused can be allowed from the chat window's **Network...** button."
