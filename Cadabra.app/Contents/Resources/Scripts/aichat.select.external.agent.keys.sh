#!/bin/sh
# aichat.select.external.agent.keys.sh
# Keys...: the Keys window for the agent the pane shows, with the place the Runs in picker names
# now (stored or not), since that is the box a login would go into.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.select.external.agent.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agent.keys.library.sh"

echo "[$(/usr/bin/basename "$0")]"

owner="$(agent_pane_owner)"
if [ -z "$owner" ] || [ "$(agent_has_keys "$owner")" != "yes" ]; then
    exit 0
fi
run_in="${OMC_ACTIONUI_VIEW_32_VALUE:-mac}"
"$pasteboard" "$KEYS_REQUEST_KEY" set "$owner$keys_tab$run_in"
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.agent.keys"
