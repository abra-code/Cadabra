#!/bin/sh
# aichat.chat.allow.folder.choose.sh
# The second step of Allow a Folder... on the line that offers it (the first is
# aichat.chat.allow.folder.offered.sh). The same handler as the button in the model bar: only
# the chooser differs, which this command opens at the folder the line names (DEFAULT_LOCATION
# in Command.json reads the line's text). The folder allowed is the one the user chooses there.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.chat.allow.folder.sh"
