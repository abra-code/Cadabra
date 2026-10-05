#!/bin/sh
# aichat.chat.allow.folder.offered.sh
# Allow a Folder... on the line that offers it after a tool call was refused a folder. It only
# hands over to aichat.chat.allow.folder.choose, whose folder chooser opens at the folder the
# line names. The two steps are needed because OMC gives a chooser the window's values as they
# were when the last command of the window ran: the line is put up from the background, after
# that, so a chooser on this command itself would open at an earlier offer's folder or at none.
# This command running is what makes the window's values current for the next one.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.chat.allow.folder.choose"
