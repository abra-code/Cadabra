#!/bin/sh
# aichat.packs.help.init.sh
# INIT_SUBCOMMAND for the sandbox packs guide's window (the layout is the model guide's,
# aichat.model.help). Loads the bundled page into its WebView.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

echo "[$(/usr/bin/basename "$0")]"

help_show_page "$OMC_ACTIONUI_WINDOW_UUID" sandbox_packs_guide.html
