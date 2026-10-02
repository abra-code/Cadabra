#!/bin/sh
# aichat.boxes.activated.sh
# The AgentVM Boxes window became the active window again (WINDOW_DID_ACTIVATE_SUBCOMMAND_ID):
# reads the boxes at once, since the user may be coming back from the AgentVM app, and makes
# sure the poll loop runs.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
[ -n "$window_uuid" ] || exit 0
boxes_refresh "$window_uuid"
boxes_ensure_poll "$window_uuid"
