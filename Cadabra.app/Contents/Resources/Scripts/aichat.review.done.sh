#!/bin/sh
# aichat.review.done.sh
# Done: the window closes; aichat.review.close.sh forgets it.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

echo "[$(/usr/bin/basename "$0")]"

"$dialog" "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok
