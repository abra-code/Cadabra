#!/bin/bash
# aichat.select.external.agent.runin.changed.sh
# The Runs in picker changed: the level picker and Use Tools follow it (agent_apply_run_in).
# Nothing is stored here. Continue stores the choice, for the agent it commits, after checking it.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.select.external.agent.library.sh"

agent_apply_run_in "${OMC_ACTIONUI_VIEW_32_VALUE:-mac}"
