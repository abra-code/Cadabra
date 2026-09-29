#!/bin/sh
# Tests/helpers/fake_install_tools.sh - curl, spctl, pkgutil and open for agentvm_install.py,
# answered from files.
#
# agentvm_install.py names these programs through CADABRA_CURL, CADABRA_SPCTL, CADABRA_PKGUTIL
# and CADABRA_OPEN. The test points each at a link to this script named after the tool, and
# this script acts by the name it was started as. Nothing reaches the network, Gatekeeper or
# Installer.
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
#   open-status      open's status (default 0); when it is not 0, nothing is installed.
#   open-sleep       seconds "Installer" stays open (default 0), for a cancel during it.
#   installs         the version the package installs, or "nothing" for an installation
#                    canceled in Installer (default: none, which also installs nothing).
#                    open makes $HOME/.local/share/agent-vm/versions/<version>/agent-vm and
#                    links $HOME/.local/bin/agent-vm to it, as agent-vm's package does. That
#                    agent-vm is $FAKE_AGENTVM when set (fake_agent_vm.sh, whose version is its
#                    own "version" file), otherwise a script printing <version>.
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
    open)
        # The package must still be there while "Installer" has it.
        package="$(last_argument "$@")"
        printf 'package-present %s\n' "$([ -f "$package" ] && echo yes || echo no)" >> "$dir/log"
        if [ -f "$dir/open-sleep" ]; then
            /bin/sleep "$(/bin/cat "$dir/open-sleep")"
        fi
        status=0
        [ -f "$dir/open-status" ] && status="$(/bin/cat "$dir/open-status")"
        if [ "$status" -ne 0 ]; then
            printf 'LSOpenURLsWithRole() failed with error -10810\n' >&2
            exit "$status"
        fi
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
