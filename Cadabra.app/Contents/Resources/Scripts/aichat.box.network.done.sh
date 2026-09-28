#!/bin/sh
# aichat.box.network.done.sh
# Done: the window closes. A rule is added when Allow is confirmed.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

"$dialog" "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok
