#!/bin/sh
# aichat.mcp.servers.box.sandbox.sh
# Paths... beside "Apply sandbox inside the VM box": a sheet saying what that sandbox lets the file
# and shell tools change and read. The lists are the ones the tools get: the project (the field
# above), and replay-box-sandbox.json, the profile copied into the box with them.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"

echo "[$(/usr/bin/basename "$0")]"

profile="$OMC_APP_BUNDLE_PATH/Contents/Resources/replay-box-sandbox.json"
project="${OMC_ACTIONUI_VIEW_310_VALUE:-}"
if [ -n "$project" ]; then
    project="\`$project\` (the project)"
else
    project="the project folder"
fi
writable="$(/usr/bin/jq -r '.read_write[] | "- `" + . + "`"' "$profile" 2>/dev/null)"
readable="$(/usr/bin/jq -r '.read_only[] | "- `" + . + "`"' "$profile" 2>/dev/null)"
mcp_info_sheet "$OMC_ACTIONUI_WINDOW_UUID" "## Sandbox inside the VM box

With the sandbox applied, the file and shell tools can **change** only:

- $project
$writable

They can also **read** macOS itself and:

$readable

The rest of the box is out of reach, including the box user's home folder, where a kept box keeps logins. The network stays as the box allows.

Without the sandbox they can read, change and run anything in the box."
