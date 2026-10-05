#!/bin/sh
# aichat.model.help.init.sh
# INIT_SUBCOMMAND for the Model Guide help window (JSON_NAME aichat.model.help).
# Loads the bundled guide into the viewer's WebView.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

echo "[$(/usr/bin/basename "$0")]"

# NIB dialogs expose their window via OMC_NIB_DLG_GUID (ActionUI windows use the
# OMC_ACTIONUI_WINDOW_UUID); fall back accordingly.
help_show_page "${OMC_ACTIONUI_WINDOW_UUID:-$OMC_NIB_DLG_GUID}" model_guide.html
