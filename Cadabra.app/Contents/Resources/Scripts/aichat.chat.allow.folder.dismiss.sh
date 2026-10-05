#!/bin/sh
# aichat.chat.allow.folder.dismiss.sh
# Dismiss on the line that offers Allow a Folder... after a refused tool call: the line goes and
# its folder is not offered again in this window.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.allow.folder.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

allow_folder_offer_dismiss "$OMC_ACTIONUI_WINDOW_UUID"
