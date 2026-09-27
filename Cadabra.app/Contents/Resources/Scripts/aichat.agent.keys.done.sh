#!/bin/sh
# aichat.agent.keys.done.sh
# Done: the window closes. Every change was saved when it was made.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agent.keys.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
"$dialog" "$window_uuid" omc_window omc_terminate_ok
