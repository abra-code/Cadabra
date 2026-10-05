#!/bin/sh
# Cadabra.main.sh - the main command's script, and the whole of what happens at launch.
#
# THE FILENAME IS THE WIRING. The main command is the first entry in COMMAND_LIST and has
# no COMMAND_ID, so the engine resolves its script from the command's NAME:
# OmcExecutor.cp builds "<NAME>.main" and falls back to a literal "main". NAME is "Cadabra",
# so this file must be Cadabra.main.sh. Renaming the app without renaming this file is not
# an error anyone sees - CreateScriptPathAndShell logs "unable to find script file" and
# returns, so the applet launches, opens nothing, and reports nothing. That is exactly what
# happened between the AIChat -> Cadabra rename and this comment: the file was still called
# AIChat.main.sh. Tests/98-command-wiring.test.sh now asserts the binding for every command.
#
# ACTIVATION_MODE is absent and therefore act_always, which is what lets this run on a bare
# double-click with no file context.

echo "[$(/usr/bin/basename "$0")]"
echo "OMC_CURRENT_COMMAND_GUID: ${OMC_CURRENT_COMMAND_GUID}"

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

echo "AICHAT_MODEL_PATH = $AICHAT_MODEL_PATH"
echo "OMC_OBJ_PATH = $OMC_OBJ_PATH"

# The branch is why this command chains imperatively with omc_next_command rather than
# declaratively with NEXT_COMMAND_ID the way the batch-conversion applets do: the two
# outcomes are different WINDOWS, so the choice cannot be made after one of them has opened.
# Whatever this launch turns out to be, it is not the one that armed the first-run handoff
# before it - the pasteboard outlives the app, so an arm stranded by a crash before the browser
# could claim it is still here. Cleared unconditionally, on every launch; the start window's
# Download Models button is what arms it again (aichat.start.choose.sh). See hf_first_run_arm.
hf_first_run_clear

if [ -n "$AICHAT_MODEL_PATH" ] || [ -n "$OMC_OBJ_PATH" ]; then
	# a model file bundled, or a file or folder dropped on the app icon
	"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.chat"
else
	# Nothing to open yet: the start window, which offers what the File menu does - a local
	# model, an external agent, an empty chat window, or the model downloads. It used to be
	# the Local Models list (or the downloads on a Mac with no model), which chose for the
	# user that this launch was about a local model.
	"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.start"
fi
