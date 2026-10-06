#!/bin/sh
# aichat.mcp.servers.packs.reveal.sh
# Reveal User Packs in the Choose Packs sheet: the folder of the user's own packs opens in the
# Finder, made first when no pack was saved yet. The sheet stays as it is; a pack file removed
# or added there shows the next time the sheet opens.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

# The program that opens the folder; a test names another.
open_tool="${CADABRA_OPEN_TOOL:-/usr/bin/open}"
folder="$mcp_app_support/SandboxPacks"

/bin/mkdir -p "$folder" 2>/dev/null
if [ ! -d "$folder" ]; then
    "$alert" --level "stop" --title "$APPLET_NAME" --ok "OK" \
        "The folder of your packs could not be made. Check that ~/Library/Application Support/Cadabra is writable."
    exit 0
fi
"$open_tool" "$folder"
