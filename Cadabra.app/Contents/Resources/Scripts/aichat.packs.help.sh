#!/bin/sh
# aichat.packs.help.sh
# Help > Sandbox Packs Help, and the help buttons where sandbox packs are chosen and recorded
# (Agentic Session Tools, its Choose Packs sheet, the Record a Pack window). Opens the guide's
# window without closing the window the user is in.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

echo "[$(/usr/bin/basename "$0")]"

"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.packs.help.dialog"
