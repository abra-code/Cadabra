#!/bin/sh
# aichat.mcp.servers.cancel.sh
# User closed the dialog without confirming. Discard the queued model launch this
# dialog owns (stashed window-scoped by init) so nothing inherits it. Harmless no-op
# when the dialog was opened from the Tools menu (nothing queued).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

echo "[$(/usr/bin/basename "$0")]"

pb_set "aichatv2_launch_${OMC_ACTIONUI_WINDOW_UUID}" ""
pb_set "aichatv2_loadtarget_${OMC_ACTIONUI_WINDOW_UUID}" ""
pb_set "aichatv2_toolsbox_${OMC_ACTIONUI_WINDOW_UUID}" ""
pb_set "aichatv2_toolsrunin_${OMC_ACTIONUI_WINDOW_UUID}" ""
# The boxes and images listed for Where tools run (agent_load_places).
/bin/rm -f "${TMPDIR:-/tmp}/cadabra-runin-places.${OMC_ACTIONUI_WINDOW_UUID}"
pb_set "aichatv2_toolsboxpane_${OMC_ACTIONUI_WINDOW_UUID}" ""
