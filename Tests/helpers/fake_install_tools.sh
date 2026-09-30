#!/bin/sh
# Tests/helpers/fake_install_tools.sh - curl, spctl, pkgutil and installer for agentvm_install.py,
# answered from files.
#
# agentvm_install.py names these programs through CADABRA_CURL, CADABRA_SPCTL, CADABRA_PKGUTIL
# and CADABRA_INSTALLER. The test points each at a link to this script named after the tool, and
# this script acts by the name it was started as. Nothing reaches the network, Gatekeeper or
# the real installer.
#
# -- The state directory ($FAKE_INSTALL_DIR) -------------------------------------
#   log              APPENDED to, one line per call: the tool's name and its arguments.
#   release.json     GitHub's answer about the newest release, which curl writes to --output.
#   release-code     the HTTP status curl reports for it (default 200).
#   curl-fail        when present, curl prints it to stderr and exits 6, as with no network.
#   package-bytes    how many bytes the download writes (default 1000).
#   download-fail    when present, the download prints it to stderr and exits 22.
#   download-sleep   seconds the download takes before it writes (default 0), for a cancel.
#   spctl.out        spctl's words (default: accepted, as notarized Developer ID software).
#   spctl-status     spctl's status (default 0).
#   pkgutil.out      pkgutil's words (default: signed by the team T9NM2ZLDTY).
#   parts            the package's choice identifiers, one per line, that installer
#                    -showChoiceChangesXML lists (default: agent-vm's two, the agent-vm part
#                    and the PATH part).
#   parts-status     when present, listing the parts fails with this status.
#   sticky           a choice identifier that -showChoicesAfterApplyingChangesXML reports
#                    selected whatever the changes file says, as one part tied to another.
#   installer-status installer's status when installing (default 0); when it is not 0, it
#                    prints an error and nothing is installed.
#   installer-sleep  seconds installing takes (default 0), for a cancel during it.
#   installs         the version the package installs, or "nothing" for an installation that
#                    reports success and installs nothing (default: none, the same).
#                    installer makes $HOME/.local/share/agent-vm/versions/<version>/agent-vm
#                    and links $HOME/.local/bin/agent-vm to it, as agent-vm's package does.
#                    That agent-vm is $FAKE_AGENTVM when set (fake_agent_vm.sh, whose version
#                    is its own "version" file, which installer then sets to <version>),
#                    otherwise a script printing <version>.
#   The log also gets "package-present yes|no" for each install, and "choice <id> <setting>"
#   for each entry of the -applyChoiceChangesXML file.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".

dir="${FAKE_INSTALL_DIR:?FAKE_INSTALL_DIR is not set}"
tool="$(/usr/bin/basename "$0")"
printf '%s %s\n' "$tool" "$*" >> "$dir/log"

# option_value <name> <args...>  ->  the argument after the first <name>.
option_value() {
    ov_name="$1"
    shift
    while [ $# -gt 0 ]; do
        if [ "$1" = "$ov_name" ]; then
            printf '%s\n' "${2:-}"
            return 0
        fi
        shift
    done
}

# last_argument <args...>
last_argument() {
    la_last=""
    for la_arg in "$@"; do
        la_last="$la_arg"
    done
    printf '%s\n' "$la_last"
}

case "$tool" in
    curl)
        output="$(option_value --output "$@")"
        if [ -f "$dir/curl-fail" ]; then
            /bin/cat "$dir/curl-fail" >&2
            exit 6
        fi
        write_out="$(option_value --write-out "$@")"
        if [ -n "$write_out" ]; then
            # The release query.
            [ -f "$dir/release.json" ] && /bin/cp "$dir/release.json" "$output"
            code=200
            [ -f "$dir/release-code" ] && code="$(/bin/cat "$dir/release-code")"
            printf '%s' "$code"
            exit 0
        fi
        # The download.
        if [ -f "$dir/download-sleep" ]; then
            /bin/sleep "$(/bin/cat "$dir/download-sleep")"
        fi
        if [ -f "$dir/download-fail" ]; then
            /bin/cat "$dir/download-fail" >&2
            exit 22
        fi
        bytes=1000
        [ -f "$dir/package-bytes" ] && bytes="$(/bin/cat "$dir/package-bytes")"
        /usr/bin/head -c "$bytes" /dev/zero > "$output"
        exit 0 ;;
    spctl)
        if [ -f "$dir/spctl.out" ]; then
            /bin/cat "$dir/spctl.out" >&2
        else
            printf '%s: accepted\nsource=Notarized Developer ID\n' "$(last_argument "$@")" >&2
        fi
        status=0
        [ -f "$dir/spctl-status" ] && status="$(/bin/cat "$dir/spctl-status")"
        exit "$status" ;;
    pkgutil)
        if [ -f "$dir/pkgutil.out" ]; then
            /bin/cat "$dir/pkgutil.out"
        else
            printf 'Package "%s":\n' "$(/usr/bin/basename "$(last_argument "$@")")"
            printf '   Status: signed by a developer certificate issued by Apple for distribution\n'
            printf '   Notarization: trusted by the Apple notary service\n'
            printf '   Certificate Chain:\n'
            printf '    1. Developer ID Installer: Tomasz Kukielka (T9NM2ZLDTY)\n'
            printf '       Expires: 2031-01-01 00:00:00 +0000\n'
            printf '    2. Developer ID Certification Authority\n'
            printf '    3. Apple Root CA\n'
        fi
        exit 0 ;;
    installer)
        package="$(option_value -pkg "$@")"
        if [ "$1" = "-showChoiceChangesXML" ] && [ -f "$dir/parts-status" ]; then
            printf 'installer: Error trying to locate CurrentUserHomeDirectory domain\n' >&2
            exit "$(/bin/cat "$dir/parts-status")"
        fi
        if [ "$1" = "-showChoicesAfterApplyingChangesXML" ]; then
            # The changes file applied, except that a part named in "sticky" stays selected.
            printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<array>\n'
            /usr/bin/plutil -convert json -o - "$2" \
                | /usr/bin/jq -r '.[] | "\(.choiceIdentifier) \(.attributeSetting)"' \
                | while read -r part setting; do
                    [ -f "$dir/sticky" ] && [ "$part" = "$(/bin/cat "$dir/sticky")" ] && setting=1
                    printf '<dict><key>attributeSetting</key><integer>%s</integer><key>choiceAttribute</key><string>selected</string><key>choiceIdentifier</key><string>%s</string></dict>\n' "$setting" "$part"
                done
            printf '</array>\n</plist>\n'
            exit 0
        fi
        if [ "$1" = "-showChoiceChangesXML" ]; then
            parts="$(printf 'com_abracode_pkg_agent_vm_choice\ncom_abracode_pkg_agent_vm_path_choice\n')"
            [ -f "$dir/parts" ] && parts="$(/bin/cat "$dir/parts")"
            printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<array>\n'
            printf '%s\n' "$parts" | while read -r part; do
                [ -n "$part" ] || continue
                printf '<dict><key>attributeSetting</key><true/><key>choiceAttribute</key><string>visible</string><key>choiceIdentifier</key><string>%s</string></dict>\n' "$part"
                printf '<dict><key>attributeSetting</key><integer>1</integer><key>choiceAttribute</key><string>selected</string><key>choiceIdentifier</key><string>%s</string></dict>\n' "$part"
            done
            printf '</array>\n</plist>\n'
            exit 0
        fi
        # The package must still be there while it is installed.
        printf 'package-present %s\n' "$([ -f "$package" ] && echo yes || echo no)" >> "$dir/log"
        changes="$(option_value -applyChoiceChangesXML "$@")"
        if [ -n "$changes" ]; then
            /usr/bin/plutil -convert json -o - "$changes" \
                | /usr/bin/jq -r '.[] | "choice \(.choiceIdentifier) \(.attributeSetting)"' >> "$dir/log"
        fi
        printf 'installer:PHASE:Preparing for installation...\ninstaller:%%10.000000\n'
        if [ -f "$dir/installer-sleep" ]; then
            /bin/sleep "$(/bin/cat "$dir/installer-sleep")"
        fi
        status=0
        [ -f "$dir/installer-status" ] && status="$(/bin/cat "$dir/installer-status")"
        if [ "$status" -ne 0 ]; then
            printf 'installer: Error - The Installer encountered an error that caused the installation to fail.\n'
            exit "$status"
        fi
        printf 'installer:%%50.000000\ninstaller:STATUS:Running package scripts...\ninstaller:%%100.000000\n'
        version=""
        [ -f "$dir/installs" ] && version="$(/bin/cat "$dir/installs")"
        case "$version" in
            ''|nothing) exit 0 ;;
        esac
        folder="$HOME/.local/share/agent-vm/versions/$version"
        /bin/mkdir -p "$folder" "$HOME/.local/bin"
        /bin/rm -f "$folder/agent-vm"
        if [ -n "${FAKE_AGENTVM:-}" ]; then
            /bin/ln -s "$FAKE_AGENTVM" "$folder/agent-vm"
            # The fake agent-vm reports the version it was installed as.
            [ -n "${FAKE_AGENTVM_DIR:-}" ] && printf '%s\n' "$version" > "$FAKE_AGENTVM_DIR/version"
        else
            printf '#!/bin/sh\necho %s\n' "$version" > "$folder/agent-vm"
            /bin/chmod +x "$folder/agent-vm"
        fi
        /bin/rm -f "$HOME/.local/bin/agent-vm"
        /bin/ln -s "../share/agent-vm/versions/$version/agent-vm" "$HOME/.local/bin/agent-vm"
        exit 0 ;;
esac
printf 'fake_install_tools.sh: started as %s, which it does not play\n' "$tool" >&2
exit 127
