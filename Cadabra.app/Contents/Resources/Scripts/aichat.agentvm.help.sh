#!/bin/sh
# aichat.agentvm.help.sh
# Help > AgentVM Boxes Help, and the help buttons of the windows that deal with boxes. Opens the
# AgentVM guide's window without closing the window the user is in.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

echo "[$(/usr/bin/basename "$0")]"

"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.agentvm.help.dialog"
