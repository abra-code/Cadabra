#!/bin/sh
# Tests/49-help-pages.test.sh - the Help windows each load their own page, the AgentVM guide
# sends the reader to the same download page as the application's own button, and the sandbox
# packs guide names every pack that comes with the application.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

HELP="$OMC_APP_BUNDLE_PATH/Contents/Resources/Help"
WEBVIEW_ID=2

# ends_with <text> <end>  ->  yes or no.
ends_with() {
    case "$1" in
        *"$2") echo yes ;;
        *)     echo no ;;
    esac
}

# -----------------------------------------------------------------------------------------
section "the pages are in the application"
check_exists "the model guide"   "$HELP/model_guide.html"
check_exists "the AgentVM guide" "$HELP/agentvm_guide.html"
check "the AgentVM guide is plain ASCII" "" "$(LC_ALL=C /usr/bin/grep -n '[^ -~]' "$HELP/agentvm_guide.html" | /usr/bin/tr -d '\t' | /usr/bin/head -3)"
check_exists "the sandbox packs guide" "$HELP/sandbox_packs_guide.html"
check "the sandbox packs guide is plain ASCII" "" "$(LC_ALL=C /usr/bin/grep -n '[^ -~]' "$HELP/sandbox_packs_guide.html" | /usr/bin/tr -d '\t' | /usr/bin/head -3)"

# -----------------------------------------------------------------------------------------
section "each window loads its own page"
cad_reset
omc_run aichat.model.help.init
url=$(ui_value "$WEBVIEW_ID")
check "the model guide's window: a file address" "file:///" "$(printf '%s' "$url" | /usr/bin/cut -c1-8)"
check "  of the model guide"                     "yes" "$(ends_with "$url" "/Contents/Resources/Help/model_guide.html")"
cad_reset
omc_run aichat.agentvm.help.init
url=$(ui_value "$WEBVIEW_ID")
check "the AgentVM guide's window: a file address" "file:///" "$(printf '%s' "$url" | /usr/bin/cut -c1-8)"
check "  of the AgentVM guide"                     "yes" "$(ends_with "$url" "/Contents/Resources/Help/agentvm_guide.html")"

cad_reset
omc_run aichat.packs.help.init
url=$(ui_value "$WEBVIEW_ID")
check "the sandbox packs guide's window: a file address" "file:///" "$(printf '%s' "$url" | /usr/bin/cut -c1-8)"
check "  of the sandbox packs guide"                     "yes" "$(ends_with "$url" "/Contents/Resources/Help/sandbox_packs_guide.html")"

# -----------------------------------------------------------------------------------------
section "the buttons open the guide's window"
cad_reset
/bin/rm -f "$OMCTEST_UI/chain.log"
OMC_CURRENT_COMMAND_GUID=help-test-1 omc_run aichat.agentvm.help
check "the next command is the window's" "aichat.agentvm.help.dialog" "$(/bin/cat "$OMCTEST_UI/chain.log" 2>/dev/null)"
/bin/rm -f "$OMCTEST_UI/chain.log"
OMC_CURRENT_COMMAND_GUID=help-test-2 omc_run aichat.packs.help
check "the sandbox packs help button's next command is its window's" "aichat.packs.help.dialog" "$(/bin/cat "$OMCTEST_UI/chain.log" 2>/dev/null)"
BASE="$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj"
for document in aichat.mcp.servers aichat.mcp.servers.packs aichat.packs.record MainMenu; do
    check "  $document has a way to it" "1" "$(/usr/bin/grep -c '"actionID": "aichat.packs.help"' "$BASE/$document.json")"
done

# -----------------------------------------------------------------------------------------
section "the sandbox packs guide names every pack that comes with the application"
SEEDS="$OMC_APP_BUNDLE_PATH/Contents/Resources/SandboxPacks"
unnamed=""
for pack in "$SEEDS"/*.json; do
    title="$(/usr/bin/jq -r .title "$pack")"
    if [ "$(/usr/bin/grep -c -F "<b>$title</b>" "$HELP/sandbox_packs_guide.html")" = "0" ]; then
        unnamed="$unnamed [$title]"
    fi
done
check "by its title" "" "$unnamed"
check "and says where a pack of the user's own is kept" "1" "$(/usr/bin/grep -c 'Application Support/Cadabra/SandboxPacks' "$HELP/sandbox_packs_guide.html")"

# -----------------------------------------------------------------------------------------
section "the guide names the application's download page"
page=$(cad_lib_var agentvm_app_page aichat.agentvm.library.sh)
check "the library has one"   "https://" "$(printf '%s' "$page" | /usr/bin/cut -c1-8)"
check "the guide links to it" "1" "$(/usr/bin/grep -c "href=\"$page\"" "$HELP/agentvm_guide.html")"

check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end
