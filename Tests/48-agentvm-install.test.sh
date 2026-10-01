#!/bin/sh
# Tests/48-agentvm-install.test.sh - installing AgentVM from its GitHub release when the
# installed agent-vm is missing or too old: agentvm_install.py's steps and refusals, the install
# job, the Box Manager's Install AgentVM... button, and the offer at chat start.
#
# Nothing reaches the network, Gatekeeper or the real installer: curl, spctl, pkgutil and
# installer are fake_install_tools.sh (CADABRA_CURL, CADABRA_SPCTL, CADABRA_PKGUTIL,
# CADABRA_INSTALLER), whose installer lays out ~/.local the way agent-vm's package does, in
# the isolated $HOME. The installed agent-vm is fake_agent_vm.sh behind that link. No
# CADABRA_AGENT_VM here: what is tested is the installed origin itself.
#
# Needs the sandbox off (the job runner). POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

cad_import_ids aichat.boxes.library.sh ""

unset CADABRA_AGENT_VM AGENT_VM_HOME

LIB=aichat.agentvm.library.sh
PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
INSTALL_PY="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_install.py"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
LINK="$HOME/.local/bin/agent-vm"
JOBS="$HOME/Library/Application Support/Cadabra/Jobs"
MIN_VERSION=$(/usr/bin/sed -n 's/^AGENTVM_MIN_VERSION="\(.*\)"$/\1/p' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh")
# A release newer than anything Cadabra requires.
NEWEST="99.0.1"
TAB=$(printf '\t')

TOOLS="$OMCTEST_WORK/tools"
/bin/mkdir -p "$TOOLS"
for t_tool in curl spctl pkgutil installer; do
    /bin/ln -sf "$OMCTEST_TESTS/helpers/fake_install_tools.sh" "$TOOLS/$t_tool"
done
CADABRA_CURL="$TOOLS/curl"
CADABRA_SPCTL="$TOOLS/spctl"
CADABRA_PKGUTIL="$TOOLS/pkgutil"
CADABRA_INSTALLER="$TOOLS/installer"
FAKE_INSTALL_DIR="$OMCTEST_WORK/install"
FAKE_AGENTVM="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
# The installed agent-vm runs the fake through links, so it cannot find its fixtures beside itself.
FAKE_AGENTVM_FIXTURES="$FIXTURES"
export CADABRA_CURL CADABRA_SPCTL CADABRA_PKGUTIL CADABRA_INSTALLER FAKE_INSTALL_DIR FAKE_AGENTVM FAKE_AGENTVM_DIR FAKE_AGENTVM_FIXTURES

lib() { cad_call_lib "$LIB" "$@"; }
col() { /usr/bin/cut -f"$1"; }

# release <version> [asset names...] - GitHub's answer about the newest release: tag v<version>,
# and agent-vm_<version>.pkg unless other assets are named. Each asset is 1000 bytes.
release() {
    r_version="$1"
    shift
    [ $# -gt 0 ] || set -- "agent-vm_$r_version.pkg"
    {
        printf '{"tag_name": "v%s", "draft": false, "prerelease": false, "assets": [' "$r_version"
        r_sep=""
        for r_name in "$@"; do
            printf '%s{"name": "%s", "size": 1000, "browser_download_url": "https://github.com/abra-code/agent-vm/releases/download/v%s/%s"}' "$r_sep" "$r_name" "$r_version" "$r_name"
            r_sep=", "
        done
        printf ']}\n'
    } > "$FAKE_INSTALL_DIR/release.json"
}

# install_reset - no agent-vm installed, the newest release NEWEST, whose package installs it.
install_reset() {
    /bin/rm -rf "$FAKE_INSTALL_DIR" "$FAKE_AGENTVM_DIR" "$HOME/.local"
    /bin/mkdir -p "$FAKE_INSTALL_DIR" "$FAKE_AGENTVM_DIR"
    release "$NEWEST"
    printf '%s\n' "$NEWEST" > "$FAKE_INSTALL_DIR/installs"
    printf '%s\n' "$NEWEST" > "$FAKE_AGENTVM_DIR/version"
    /usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
}

# run_install [--min V]  ->  agentvm_install.py's status; its stdout and stderr in out and err.
run_install() {
    ri_min="$MIN_VERSION"
    [ "${1:-}" = "--min" ] && ri_min="$2"
    "$PY" "$INSTALL_PY" install --api "https://api.github.com/repos/abra-code/agent-vm/releases/latest" \
        --min "$ri_min" --team T9NM2ZLDTY --link "$LINK" > "$OMCTEST_WORK/out" 2> "$OMCTEST_WORK/err"
    echo $?
}
error_line() { /usr/bin/sed -n 's/^Error: //p' "$OMCTEST_WORK/err"; }
# The events are json.dumps lines, so "step" always follows "event" in this exact spelling.
steps() {
    /usr/bin/sed -n 's/^{"event": "progress", "step": "\([^"]*\)".*/\1/p' "$OMCTEST_WORK/err" \
        | /usr/bin/uniq | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//'
}
# asked <pattern>  ->  how many calls of the fake tools matched, 0 before the first call.
asked() {
    [ -f "$FAKE_INSTALL_DIR/log" ] || { echo 0; return 0; }
    /usr/bin/grep -c "^$1" "$FAKE_INSTALL_DIR/log" | /usr/bin/tr -d ' '
}
# In $TMPDIR for a direct run, and in Cadabra's own folder for the job (agentvm_install_job).
temp_folders() { /bin/ls -d "${TMPDIR:-/tmp}"/cadabra-agentvm-install.* "$HOME/Library/Application Support/Cadabra/Run"/cadabra-agentvm-install.* 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' '; }

# job_state <id>  ->  the job's state in agentvm_jobs.
job_state() { lib agentvm_jobs | /usr/bin/awk -F'\t' -v id="$1" '$1 == id { print $5 }'; }

# wait_state <id> <state>  ->  the job's state once it is <state>, or its last (10 s at most).
wait_state() {
    w_left=100
    while :; do
        w_state=$(job_state "$1")
        [ "$w_state" = "$2" ] && break
        [ "$w_left" -le 0 ] && break
        w_left=$((w_left - 1))
        /bin/sleep 0.1
    done
    printf '%s\n' "$w_state"
}

# wait_logged <tool>  ->  once the fake has seen a call of it (5 s at most).
wait_logged() {
    w_left=50
    while [ "$(asked "$1")" = "0" ] && [ "$w_left" -gt 0 ]; do
        w_left=$((w_left - 1))
        /bin/sleep 0.1
    done
}

# wait_jobs_done - until no job runs (10 s at most).
wait_jobs_done() {
    w_left=100
    while [ "$w_left" -gt 0 ]; do
        w_running=$(/usr/bin/find "$JOBS" -name lock 2>/dev/null | while read -r w_lock; do
            [ -f "$(/usr/bin/dirname "$w_lock")/exit" ] || echo x; done | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        [ "$w_running" = "0" ] && return 0
        w_left=$((w_left - 1))
        /bin/sleep 0.1
    done
}

/bin/rm -rf "$JOBS"
temps_before=$(temp_folders)

# -----------------------------------------------------------------------------------------
section "the newest release, checked, installed without Installer's windows, then found installed"
install_reset
check "installed"                           "0" "$(run_install)"
check "  says so"                           "Installed AgentVM $NEWEST: $LINK" "$(/bin/cat "$OMCTEST_WORK/out")"
check "  every step announced, in order"    "release download verify install check done" "$(steps)"
check "  asked GitHub for the newest release, https only" "1" "$(/usr/bin/grep -c -- '--proto =https --proto-redir =https .*https://api.github.com/repos/abra-code/agent-vm/releases/latest$' "$FAKE_INSTALL_DIR/log")"
check "  downloaded the release's package"  "1" "$(/usr/bin/grep -c "^curl .*https://github.com/abra-code/agent-vm/releases/download/v$NEWEST/agent-vm_$NEWEST.pkg\$" "$FAKE_INSTALL_DIR/log")"
check "  Gatekeeper's install assessment"   "1" "$(/usr/bin/grep -c "^spctl --assess --type install --verbose .*/agent-vm_$NEWEST.pkg\$" "$FAKE_INSTALL_DIR/log")"
check "  the signature's team"              "1" "$(/usr/bin/grep -c "^pkgutil --check-signature .*/agent-vm_$NEWEST.pkg\$" "$FAKE_INSTALL_DIR/log")"
check "  its parts listed, for this user"   "1" "$(/usr/bin/grep -c "^installer -showChoiceChangesXML -pkg .*/agent-vm_$NEWEST.pkg -target CurrentUserHomeDirectory\$" "$FAKE_INSTALL_DIR/log")"
check "  installed for this user, with progress" "1" "$(/usr/bin/grep -c "^installer -pkg .*/agent-vm_$NEWEST.pkg -target CurrentUserHomeDirectory -applyChoiceChangesXML .*/choices.plist -verboseR\$" "$FAKE_INSTALL_DIR/log")"
check "  the selection confirmed first"  "1" "$(/usr/bin/grep -c "^installer -showChoicesAfterApplyingChangesXML .*/choices.plist -pkg .*/agent-vm_$NEWEST.pkg -target CurrentUserHomeDirectory\$" "$FAKE_INSTALL_DIR/log")"
check "  the agent-vm part selected"        "1" "$(/usr/bin/grep -c '^choice com_abracode_pkg_agent_vm_choice 1$' "$FAKE_INSTALL_DIR/log")"
check "  the PATH part left out"            "1" "$(/usr/bin/grep -c '^choice com_abracode_pkg_agent_vm_path_choice 0$' "$FAKE_INSTALL_DIR/log")"
check "  its progress passed on"            "1" "$(/usr/bin/grep -c '^{"event": "progress", "step": "install", "message": "Installing AgentVM '"$NEWEST"'", "fraction": 0.5}$' "$OMCTEST_WORK/err")"
check "  with the package still there"      "1" "$(/usr/bin/grep -c '^package-present yes$' "$FAKE_INSTALL_DIR/log")"
check "  and the link answers the version"  "$NEWEST" "$("$LINK" --version)"
check "the temporary folder is gone"        "$temps_before" "$(temp_folders)"

section "the release's own package is chosen among other assets"
install_reset
release "$NEWEST" "agent-vm_$NEWEST.tar.gz" "other.pkg" "agent-vm_$NEWEST.pkg"
check "installed"                   "0" "$(run_install)"
check "  from agent-vm_<version>.pkg" "1" "$(/usr/bin/grep -c "^curl .*/agent-vm_$NEWEST.pkg\$" "$FAKE_INSTALL_DIR/log")"
install_reset
release "$NEWEST" "AgentVM.pkg"
check "a single package of another name is taken" "0" "$(run_install)"
install_reset
release "$NEWEST" "a.pkg" "b.pkg"
check "two other packages are refused" "1" "$(run_install)"
check "  naming them"                  "1" "$(cad_has "$(error_line)" "several installer packages (a.pkg, b.pkg)")"
install_reset
release "$NEWEST" "agent-vm_$NEWEST.zip"
check "no package at all is refused"   "1" "$(run_install)"
check "  saying so"                    "1" "$(cad_has "$(error_line)" "The AgentVM $NEWEST release has no installer package (.pkg)")"
check "  and nothing was downloaded"   "1" "$(asked curl)"

section "GitHub's refusals, in words"
install_reset
printf '404' > "$FAKE_INSTALL_DIR/release-code"
check "no release (a private repository answers the same)" "1" "$(run_install)"
check "  says where it looked"         "1" "$(cad_has "$(error_line)" "No AgentVM release was found at https://github.com/abra-code/agent-vm/releases")"
check "  and downloads nothing"        "1" "$(asked curl)"
install_reset
printf '403' > "$FAKE_INSTALL_DIR/release-code"
check "a rate limit"                   "1" "$(run_install)"
check "  says to try later"            "1" "$(cad_has "$(error_line)" "limit on requests. Try again later")"
install_reset
printf 'Could not resolve host: api.github.com\n' > "$FAKE_INSTALL_DIR/curl-fail"
check "no network"                     "1" "$(run_install)"
check "  in curl's words"              "1" "$(cad_has "$(error_line)" "Could not reach GitHub to look for AgentVM releases: Could not resolve host: api.github.com")"
install_reset
printf 'not json' > "$FAKE_INSTALL_DIR/release.json"
check "an answer that is not JSON"     "1" "$(run_install)"
install_reset
release "latest"
check "a tag that is not a version"    "1" "$(run_install)"
check "  says so"                      "1" "$(cad_has "$(error_line)" "tagged 'vlatest', which is not a version")"

section "a release older than Cadabra needs is not downloaded"
install_reset
release "0.0.1"
check "refused"                        "1" "$(run_install)"
check "  naming both versions"         "1" "$(cad_has "$(error_line)" "The newest AgentVM release is 0.0.1, and Cadabra needs $MIN_VERSION or later")"
check "  and nothing was downloaded"   "1" "$(asked curl)"
install_reset
release "$MIN_VERSION"
printf '%s\n' "$MIN_VERSION" > "$FAKE_INSTALL_DIR/installs"
printf '%s\n' "$MIN_VERSION" > "$FAKE_AGENTVM_DIR/version"
check "the minimum itself is fine"     "0" "$(run_install)"

section "a download that fails or comes out short is never installed"
install_reset
printf 'The requested URL returned error: 404\n' > "$FAKE_INSTALL_DIR/download-fail"
check "a failed download"              "1" "$(run_install)"
check "  in curl's words"              "1" "$(cad_has "$(error_line)" "Could not download agent-vm_$NEWEST.pkg: The requested URL returned error: 404")"
check "  not checked, not installed"   "0 0" "$(asked spctl) $(asked "installer -pkg")"
install_reset
printf '999\n' > "$FAKE_INSTALL_DIR/package-bytes"
check "a short download"               "1" "$(run_install)"
check "  says so"                      "1" "$(cad_has "$(error_line)" "is 999 bytes, and GitHub lists it as 1000")"
check "  not installed"                "0" "$(asked "installer -pkg")"
check "the temporary folders are gone after failures too" "$temps_before" "$(temp_folders)"

section "a package that is not notarized, or not AgentVM's, is never installed"
install_reset
printf 'agent-vm.pkg: rejected\nsource=no usable signature\n' > "$FAKE_INSTALL_DIR/spctl.out"
printf '3\n' > "$FAKE_INSTALL_DIR/spctl-status"
check "rejected by Gatekeeper"         "1" "$(run_install)"
check "  says why"                     "1" "$(cad_has "$(error_line)" "is not notarized Developer ID software, so Cadabra does not install it (agent-vm.pkg: rejected source=no usable signature)")"
check "  not installed"                "0" "$(asked "installer -pkg")"
install_reset
printf 'agent-vm.pkg: accepted\nsource=Developer ID\n' > "$FAKE_INSTALL_DIR/spctl.out"
check "accepted but not notarized"     "1" "$(run_install)"
check "  not installed"                "0" "$(asked "installer -pkg")"
install_reset
printf '   Certificate Chain:\n    1. Developer ID Installer: Someone Else (ABCDE12345)\n    2. Developer ID Certification Authority\n' > "$FAKE_INSTALL_DIR/pkgutil.out"
check "another team's package"         "1" "$(run_install)"
check "  names both teams"             "1" "$(cad_has "$(error_line)" "signed by the Developer ID team ABCDE12345, not AgentVM's (T9NM2ZLDTY)")"
check "  not installed"                "0" "$(asked "installer -pkg")"
install_reset
printf '   Certificate Chain:\n    1. Developer ID Installer: Mallory (T9NM2ZLDTY) (ABCDE12345)\n' > "$FAKE_INSTALL_DIR/pkgutil.out"
check "a name that quotes AgentVM's team is another team" "1" "$(run_install)"
check "  the real one named"           "1" "$(cad_has "$(error_line)" "team ABCDE12345")"
install_reset
printf '   Certificate Chain:\n    1. Developer ID Application: Tomasz Kukielka (T9NM2ZLDTY)\n' > "$FAKE_INSTALL_DIR/pkgutil.out"
check "an Application certificate is not an Installer one" "1" "$(run_install)"
check "  not installed"                "0" "$(asked "installer -pkg")"

section "a package whose parts are not agent-vm's"
install_reset
printf 'com_abracode_pkg_agent_vm_choice\ncom_abracode_pkg_agent_vm_path_choice\ncom_abracode_pkg_agent_vm_extra_choice\n' > "$FAKE_INSTALL_DIR/parts"
check "a part added later"             "0" "$(run_install)"
check "  is left out until named"      "1" "$(/usr/bin/grep -c '^choice com_abracode_pkg_agent_vm_extra_choice 0$' "$FAKE_INSTALL_DIR/log")"
install_reset
printf 'com_example_other_choice\ncom_abracode_pkg_agent_vm_path_choice\n' > "$FAKE_INSTALL_DIR/parts"
check "no agent-vm part is refused"    "1" "$(run_install)"
check "  naming the part"              "1" "$(cad_has "$(error_line)" "has no agent-vm part (com_abracode_pkg_agent_vm_choice)")"
check "  not installed"                "0" "$(asked "installer -pkg")"
install_reset
printf 'com_abracode_pkg_agent_vm_path_choice\n' > "$FAKE_INSTALL_DIR/sticky"
check "a PATH part that stays selected is refused" "1" "$(run_install)"
check "  naming it"                     "1" "$(cad_has "$(error_line)" "does not let Cadabra install only its agent-vm part (com_abracode_pkg_agent_vm_path_choice)")"
check "  not installed"                "0" "$(asked "installer -pkg")"
install_reset
printf '1\n' > "$FAKE_INSTALL_DIR/parts-status"
check "parts installer cannot list"    "1" "$(run_install)"
check "  in its words"                 "1" "$(cad_has "$(error_line)" "installer could not list the parts of agent-vm_$NEWEST.pkg: installer: Error trying to locate CurrentUserHomeDirectory domain")"
check "  not installed"                "0" "$(asked "installer -pkg")"

section "installing did not install it"
install_reset
printf 'nothing\n' > "$FAKE_INSTALL_DIR/installs"
check "a failure"                      "1" "$(run_install)"
check "  that says so"                 "1" "$(cad_has "$(error_line)" "The installation ended, and AgentVM $NEWEST is not installed")"
install_reset
printf '0.0.2\n' > "$FAKE_INSTALL_DIR/installs"
printf '0.0.2\n' > "$FAKE_AGENTVM_DIR/version"
check "another version at the link"   "1" "$(run_install)"
check "  names what it reports"        "1" "$(cad_has "$(error_line)" "$LINK reports 0.0.2")"
install_reset
printf '1\n' > "$FAKE_INSTALL_DIR/installer-status"
check "installer failed"               "1" "$(run_install)"
check "  in its words"                 "1" "$(cad_has "$(error_line)" "Could not install agent-vm_$NEWEST.pkg: installer: Error - The Installer encountered an error")"
check "  without its progress lines"   "0" "$(cad_has "$(error_line)" "installer:%")"
install_reset
printf '5\n' > "$FAKE_INSTALL_DIR/installer-sleep"
check "installing that stalls is stopped" "1" "$(CADABRA_INSTALL_TIMEOUT=1 run_install)"
check "  saying so"                     "1" "$(cad_has "$(error_line)" "did not finish within")"

section "arguments the script refuses"
out=$("$PY" "$INSTALL_PY" install --api x --min 1.x --team T --link "$LINK" 2>&1); rc=$?
check "a minimum that is not a version" "2" "$rc"
out=$("$PY" "$INSTALL_PY" install --api x --min 1.0 --team T --link relative/agent-vm 2>&1); rc=$?
check "a relative link"                 "2" "$rc"

# -----------------------------------------------------------------------------------------
section "the library: missing and too old are told apart"
install_reset
cad_reset
out=$(lib agentvm_available); rc=$?
check "nothing installed"              "2" "$rc"
/bin/mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\necho 0.0.1\n' > "$HOME/.local/bin/agent-vm"
/bin/chmod +x "$HOME/.local/bin/agent-vm"
out=$(lib agentvm_available); rc=$?
check "an old one"                     "3" "$rc"
/bin/rm -rf "$HOME/.local"
out=$( ( CADABRA_AGENT_VM="$OMCTEST_WORK/nowhere"; export CADABRA_AGENT_VM; lib agentvm_available ) ); rc=$?
check "a test seam that is missing is not an install away" "1" "$rc"

section "the install job"
install_reset
/bin/rm -rf "$JOBS"
job=$(lib agentvm_install_job install); rc=$?
check "starts"                         "0" "$rc"
check "  and ends done"                "done" "$(wait_state "$job" done)"
row=$(lib agentvm_jobs | /usr/bin/awk -F'\t' -v id="$job" '$1 == id')
check "  kind, target, title"          "agentvm-install${TAB}agentvm:AgentVM${TAB}Install AgentVM" "$(printf '%s\n' "$row" | col 2-4)"
check "  its last step"                "done" "$(printf '%s\n' "$row" | col 9)"
check "agent-vm can be used now"       "0" "$(lib agentvm_available >/dev/null; echo $?)"
# The Local server's sandbox may write to $TMPDIR: a package checked there could be replaced
# before installer reads it.
check "the job checked and installed the package in Cadabra's own folder, not \$TMPDIR" "1|1|all" \
    "$(asked "spctl .*Application Support/Cadabra/Run/cadabra-agentvm-install\.")|$(asked "installer -pkg .*Application Support/Cadabra/Run/cadabra-agentvm-install\.")|$([ "$(asked "installer -pkg ")" = "$(asked "installer -pkg .*Application Support/Cadabra/Run/cadabra-agentvm-install\.")" ] && echo all)"
install_reset
printf '2\n' > "$FAKE_INSTALL_DIR/installer-sleep"
job=$(lib agentvm_install_job update)
wait_logged "installer -pkg"
second=$(lib agentvm_install_job install); rc=$?
check "a second install while one runs is refused" "3" "$rc"
check "  saying which"                 "1" "$(cad_has "$(lib agentvm_last_error "$rc")" "Update AgentVM is still running for AgentVM")"
check "while it runs, agentvm_installing says so" "0" "$(lib agentvm_installing; echo $?)"
lib agentvm_job_cancel "$job" >/dev/null
check "a cancel while installing is only noted" "done" "$(wait_state "$job" done)"
check "  and AgentVM is installed"     "$NEWEST" "$("$LINK" --version)"
install_reset
printf '5\n' > "$FAKE_INSTALL_DIR/download-sleep"
job=$(lib agentvm_install_job install)
wait_logged "curl .*--output .*agent-vm_"
lib agentvm_job_cancel "$job" >/dev/null
check "a cancel during the download stops it" "canceled" "$(wait_state "$job" canceled)"
check "  before anything was installed"   "0" "$(asked "installer -pkg")"
check "  and its temporary folder is gone" "$temps_before" "$(temp_folders)"
check "nothing runs now"               "1" "$(lib agentvm_installing; echo $?)"

# -----------------------------------------------------------------------------------------
# open_window - a fresh Box Manager, as the menu item opens it.
open_window() {
    ui_reset
    omc_control_defaults aichat.boxes
    omc_run aichat.boxes.init
}

section "Box Manager: nothing installed"
install_reset
/bin/rm -rf "$JOBS"
cad_reset
open_window
check "the header says so"             "AgentVM is not installed" "$(ui_value "$BOXES_HEADER_ID")"
check "  and where to get it"          "1" "$(cad_has "$(ui_value "$BOXES_NOTES_ID")" "https://github.com/abra-code/agent-vm/releases")"
check "Install AgentVM... is shown"    "1" "$(ui_visible "$BOXES_INSTALL_ID")"
check "  by that name"                 "Install AgentVM..." "$(ui_prop "$BOXES_INSTALL_ID" title)"
check "  and can be clicked"           "1" "$(ui_enabled "$BOXES_INSTALL_ID")"
check "the picker is off"              "0" "$(ui_enabled "$BOXES_KIND_ID")"
check "New Box is off"                 "0" "$(ui_enabled "$BOXES_NEW_BOX_ID")"
check "no poll without jobs"           "0" "$(chain_asked aichat.boxes.poll)"

section "Box Manager: too old"
/bin/mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\necho 0.0.1\n' > "$HOME/.local/bin/agent-vm"
/bin/chmod +x "$HOME/.local/bin/agent-vm"
open_window
check "the header says so"             "AgentVM needs an update" "$(ui_value "$BOXES_HEADER_ID")"
check "  the reason names the versions" "1" "$(cad_has "$(ui_value "$BOXES_NOTES_ID")" "Cadabra needs agent-vm $MIN_VERSION or later, and $LINK is 0.0.1")"
check "Update AgentVM... is shown"     "Update AgentVM..." "$(ui_prop "$BOXES_INSTALL_ID" title)"

section "Box Manager: Install AgentVM..., declined and then accepted"
install_reset
open_window
alerts_reset
alert_answer 1
omc_run aichat.boxes.agentvm.install
check "it asks first"                  "1" "$(alerts_mention "installs it for your user account only")"
check "  saying the shell is not changed" "1" "$(alerts_mention "Your shell settings are not changed")"
check "  declined: no job"             "0" "$(/bin/ls "$JOBS" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
printf '1\n' > "$FAKE_INSTALL_DIR/installer-sleep"
alert_answer 0
omc_run aichat.boxes.agentvm.install
check "  accepted: the header says it is installing" "Installing AgentVM..." "$(ui_value "$BOXES_HEADER_ID")"
check "  the button waits"             "0" "$(ui_enabled "$BOXES_INSTALL_ID")"
check "  the job is listed"            "1" "$(ui_rows "$BOXES_JOBS_ID" | /usr/bin/grep -c '^Install AgentVM')"
check "  and followed"                 "1" "$(chain_asked aichat.boxes.poll)"
inst_job=$(lib agentvm_jobs | /usr/bin/awk -F'\t' '$2 == "agentvm-install" { print $1 }' | /usr/bin/tail -1)
omc_table_cell "$BOXES_JOBS_ID" 4 "$inst_job"
alerts_reset
alert_answer 1
omc_run aichat.boxes.job.cancel
check "Cancel Job says an install under way finishes" "1" "$(alerts_mention 'Cadabra lets it finish')"
wait_jobs_done
omc_run aichat.boxes.poll
check "once it is done, the header names agent-vm" "1" "$(cad_has "$(ui_value "$BOXES_HEADER_ID")" "(installed)")"
check "  the button is gone"           "0" "$(ui_visible "$BOXES_INSTALL_ID")"
check "  the picker is on"             "1" "$(ui_enabled "$BOXES_KIND_ID")"
check "  New Box is on"                "1" "$(ui_enabled "$BOXES_NEW_BOX_ID")"
check "  and the images are listed"    "5" "$(ui_row_count "$BOXES_IMAGES_ID")"

section "Box Manager: installed meanwhile from elsewhere"
install_reset
open_window
printf '%s\n' "$NEWEST" > "$FAKE_INSTALL_DIR/installs"
"$CADABRA_INSTALLER" -pkg "$OMCTEST_WORK/by-hand.pkg" -target CurrentUserHomeDirectory >/dev/null
alerts_reset
omc_run aichat.boxes.agentvm.install
check "nothing is asked"               "0" "$(alerts_count)"
check "  the window is simply usable"  "1" "$(ui_enabled "$BOXES_KIND_ID")"

# install_by_hand <version> - agent-vm <version> installed, as its package would, before any window.
install_by_hand() {
    printf '%s\n' "$1" > "$FAKE_INSTALL_DIR/installs"
    printf '%s\n' "$1" > "$FAKE_AGENTVM_DIR/version"
    "$CADABRA_INSTALLER" -pkg "$OMCTEST_WORK/by-hand.pkg" -target CurrentUserHomeDirectory >/dev/null
    printf '%s\n' "$NEWEST" > "$FAKE_INSTALL_DIR/installs"
}
NEWEST_FILE="$HOME/Library/Application Support/Cadabra/agentvm-newest.tsv"
# newest_asked  ->  how many times GitHub was asked for the newest release with the short limit.
newest_asked() { asked "curl .*--max-time 5 .*releases/latest"; }

section "Box Manager: a newer release than the installed agent-vm"
install_reset
/bin/rm -f "$NEWEST_FILE"
install_by_hand "$MIN_VERSION"
open_window
check "the header names the installed version" "agent-vm $MIN_VERSION (installed)" "$(ui_value "$BOXES_HEADER_ID")"
check "  GitHub was asked once, with a short limit" "1" "$(newest_asked)"
check "Update AgentVM... is shown"     "1" "$(ui_visible "$BOXES_INSTALL_ID")"
check "  by that name"                 "Update AgentVM..." "$(ui_prop "$BOXES_INSTALL_ID" title)"
check "  and can be clicked"           "1" "$(ui_enabled "$BOXES_INSTALL_ID")"
check "  the note names both versions" "1" "$(cad_has "$(ui_value "$BOXES_NOTES_ID")" "AgentVM $NEWEST is available; this Mac has $MIN_VERSION.")"
check "the window stays usable"        "1" "$(ui_enabled "$BOXES_NEW_BOX_ID")"
open_window
check "a second look the same day does not ask again" "1" "$(newest_asked)"
check "  and still shows the update"   "1" "$(ui_visible "$BOXES_INSTALL_ID")"
printf '%s\t%s\n' "$(( $(/bin/date +%s) - 86401 ))" "$NEWEST" > "$NEWEST_FILE"
open_window
check "a day later it asks again"      "2" "$(newest_asked)"
printf '%s\t%s\n' "$(( $(/bin/date +%s) + 86400 ))" "$NEWEST" > "$NEWEST_FILE"
open_window
check "a lookup dated in the future is redone" "3" "$(newest_asked)"

section "Box Manager: the newer release installed with Update AgentVM..."
alerts_reset
alert_answer 0
omc_run aichat.boxes.agentvm.install
check "it asks first"                  "1" "$(alerts_mention "Boxes that are running keep their version")"
upd_job=$(lib agentvm_jobs | /usr/bin/awk -F'\t' '$2 == "agentvm-install" { print $1 }' | /usr/bin/tail -1)
check "  an update job"                "Update AgentVM" "$(lib agentvm_jobs | /usr/bin/awk -F'\t' -v id="$upd_job" '$1 == id { print $4 }')"
check "  that ends done"               "done" "$(wait_state "$upd_job" done)"
check "  the newer version is installed" "$NEWEST" "$("$LINK" --version)"
omc_run aichat.boxes.poll
check "then the header names it"       "agent-vm $NEWEST (installed)" "$(ui_value "$BOXES_HEADER_ID")"
check "  and Update AgentVM... is gone" "0" "$(ui_visible "$BOXES_INSTALL_ID")"
check "  with no note about it"        "0" "$(cad_has "$(ui_value "$BOXES_NOTES_ID")" "is available")"

section "Box Manager: no notice without a newer release"
install_reset
/bin/rm -f "$NEWEST_FILE"
install_by_hand "$NEWEST"
open_window
check "the installed one is the newest: no Update" "0" "$(ui_visible "$BOXES_INSTALL_ID")"
install_reset
/bin/rm -f "$NEWEST_FILE"
install_by_hand "$MIN_VERSION"
printf 'Could not resolve host: api.github.com\n' > "$FAKE_INSTALL_DIR/curl-fail"
open_window
check "no network: no Update"          "0" "$(ui_visible "$BOXES_INSTALL_ID")"
check "  and no words about it"        "0" "$(cad_has "$(ui_value "$BOXES_NOTES_ID")" "is available")"
check "  the failure is kept, with no version" "" "$(/usr/bin/cut -f2 "$NEWEST_FILE")"
/bin/rm -f "$FAKE_INSTALL_DIR/curl-fail"
open_window
check "  so it is not asked again that day" "1" "$(newest_asked)"
install_reset
printf '%s\t%s\n' "$(/bin/date +%s)" "$NEWEST" > "$NEWEST_FILE"
check "a test double is never compared" "" "$( ( CADABRA_AGENT_VM="$FAKE_AGENTVM"; export CADABRA_AGENT_VM; lib agentvm_update_available 0.0.1 ) )"
check "  an installed one is"          "$NEWEST" "$(lib agentvm_update_available 0.0.1)"
check "  and a newer installed one is not" "" "$(lib agentvm_update_available 999.0)"
printf '08\t%s\n' "$NEWEST" > "$NEWEST_FILE"
check "a damaged lookup date is redone" "$NEWEST" "$(lib agentvm_update_available 0.0.1)"
printf '%s\t%s\n' "$(( $(/bin/date +%s) - 86401 ))" "$NEWEST" > "$NEWEST_FILE"
printf 'Could not resolve host: api.github.com\n' > "$FAKE_INSTALL_DIR/curl-fail"
check "an update already known outlives a failed lookup" "$NEWEST" "$(lib agentvm_update_available 0.0.1)"
check "  whose date is renewed"        "1" "$(( $(/bin/date +%s) - $(/usr/bin/cut -f1 "$NEWEST_FILE") < 60 ))"
/bin/rm -f "$FAKE_INSTALL_DIR/curl-fail"
asked_before=$(newest_asked)
/bin/rm -f "$NEWEST_FILE"
lib agentvm_update_available "" >/dev/null
check "an unknown installed version asks nothing" "$asked_before" "$(newest_asked)"
/bin/rm -f "$NEWEST_FILE"

# -----------------------------------------------------------------------------------------
# engine <function> [args...]  ->  its status, then CHAT_ENGINE_CONFIG (48-box-sessions.test.sh's).
engine() {
    ( . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.chat.engine.library.sh" >/dev/null 2>&1
      prefs="$OMCTEST_WORK/no-such-registry.plist"
      "$@" >/dev/null 2>&1
      printf '%s\n' "$?" )
}

section "chat start: an agent set to a box, with AgentVM not installed"
# No Box Manager is open (the one above belonged to an earlier window).
cad_pb_set "cadabra_boxes_manager_window_$OMC_APP_PROCESS_ID" ""
install_reset
/bin/rm -rf "$JOBS"
cad_reset
ui_reset
alerts_reset
alert_answer 1
check "the conversation does not start" "1" "$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)"
check "  the offer names the fix"      "1" "$(alerts_mention "Install AgentVM")"
check "  declined: no job"             "0" "$(/bin/ls "$JOBS" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "  and no window opened"         "0" "$(chain_asked aichat.boxes.open)"
alerts_reset
printf '2\n' > "$FAKE_INSTALL_DIR/installer-sleep"
alert_answer 0
check "accepted: still not started now" "1" "$(engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false)"
check "  the install job runs"         "1" "$(lib agentvm_jobs | /usr/bin/awk -F'\t' '$2 == "agentvm-install"' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "  and the AgentVM window opens to show it" "1" "$(chain_asked aichat.boxes.open)"
wait_logged "installer -pkg"
alerts_reset
alert_answer 0
engine chat_engine_box_transport w1 "claude-agent-acp" claude-code-acp new:dev false >/dev/null
check "again while that install runs: no second job"  "1" "$(lib agentvm_jobs | /usr/bin/awk -F'\t' '$2 == "agentvm-install"' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "  no refusal, only the offer"    "1" "$(alerts_count)"
check "  and the AgentVM window opens to show the running one" "2" "$(chain_asked aichat.boxes.open)"
wait_jobs_done

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end
