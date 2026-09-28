#!/bin/sh
# aichat.box.network.close.sh
# The window closes (Done or the close button): its context is forgotten.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

"$pasteboard" "$(boxnet_context_key "$OMC_ACTIONUI_WINDOW_UUID")" set ""
