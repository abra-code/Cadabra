#!/bin/sh
# aichat.select.local.model.toggle.sandbox.sh
# Handles the "Run Engine in Sandbox" checkbox of Select Local Model: stores the setting the next
# model load reads (inference_sandbox_enabled). A model already loaded keeps running as it was
# started.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.server.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

case "${OMC_ACTIONUI_VIEW_31_VALUE:-true}" in
    false) sandbox="false" ;;
    *)     sandbox="true" ;;
esac
inference_sandbox_set "$sandbox"

echo "saved inference sandbox=$sandbox"
