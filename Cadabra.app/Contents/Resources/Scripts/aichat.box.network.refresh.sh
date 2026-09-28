#!/bin/sh
# aichat.box.network.refresh.sh
# Refresh: reads the box's network log again.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

boxnet_paint "$OMC_ACTIONUI_WINDOW_UUID"
