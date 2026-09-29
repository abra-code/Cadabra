#!/usr/bin/env python3
"""Download AgentVM's newest release package from GitHub, check it, and open it in Installer.

Cadabra carries no agent-vm. It runs the one AgentVM's package installs for the user: the link
~/.local/bin/agent-vm, into ~/.local/share/agent-vm/versions/<version>/. When that is missing
or older than Cadabra needs, the Box Manager runs this as a job (agentvm_job.py), so it
survives the window and shows its progress in the jobs table.

Usage:
    agentvm_install.py install --api URL --min VERSION --team TEAM --link PATH

    --api   the GitHub API address of the newest release
            (https://api.github.com/repos/abra-code/agent-vm/releases/latest)
    --min   the oldest agent-vm version Cadabra accepts; an older release is refused
    --team  the Developer ID team the package must be signed by
    --link  where the package puts the link to agent-vm, checked after the install

Steps, each announced as a progress event on stderr (the JSON lines agent-vm writes, which
agentvm_job.py list reads): release, download, verify, install, check.
    release   reads the newest release: its version (the tag, without a leading "v") and its
              package, agent-vm_<version>.pkg, or the release's only .pkg. Drafts and
              pre-releases are never "latest" on GitHub.
    download  fetches the package into a new temporary folder, over https only.
    verify    the package must pass Gatekeeper's install assessment as notarized Developer ID
              software (spctl), and the first certificate of its signature must be a Developer
              ID Installer certificate of TEAM (pkgutil). Nothing unverified is ever opened.
    install   opens the package in Installer and waits until Installer quits. The user sees
              what the package installs, for them only and with no administrator password, and
              can untick its "add ~/.local/bin to your shell's PATH" part under Customize.
              Nothing here edits a shell profile or installs behind the user's back.
    check     the link must now report the release's version; when it does not, the
              installation was canceled in Installer, or failed.
The temporary folder is removed however the job ends, a system shutdown (SIGTERM) included; a
download that stays below 1000 bytes a second for a minute fails.

Cancel (SIGINT, from agentvm_job.py cancel) stops the job before the install step with status
130. Once Installer is open, a cancel is only noted: the package is Installer's until it quits,
and Installer has its own Cancel. On failure the last stderr line is "Error: <what failed and
what to do>", and the status is 1.

Test seams, like CADABRA_CURL in aichat.library.sh: CADABRA_CURL, CADABRA_SPCTL,
CADABRA_PKGUTIL and CADABRA_OPEN name the programs used in place of /usr/bin/curl,
/usr/sbin/spctl, /usr/sbin/pkgutil and /usr/bin/open.
"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

CURL = os.environ.get("CADABRA_CURL") or "/usr/bin/curl"
SPCTL = os.environ.get("CADABRA_SPCTL") or "/usr/sbin/spctl"
PKGUTIL = os.environ.get("CADABRA_PKGUTIL") or "/usr/sbin/pkgutil"
OPEN = os.environ.get("CADABRA_OPEN") or "/usr/bin/open"
INSTALLER_APP = "com.apple.installer"

RELEASES_PAGE = "https://github.com/abra-code/agent-vm/releases"
VERSION_PATTERN = re.compile(r"^[0-9]+(\.[0-9]+)*$")
# pkgutil --check-signature numbers the chain from the signing certificate: "1. Developer ID
# Installer: Name (TEAMID)". The team is the LAST parenthesized group, since a name may hold
# parentheses of its own.
SIGNER_PATTERN = re.compile(r"^\s*1\.\s+Developer ID Installer: .*\(([A-Z0-9]+)\)\s*$")


class Failure(Exception):
    """A step that failed, with the message for the user."""


class Canceled(Exception):
    """Cancel was asked for."""


def event(step, message, fraction=None):
    line = {"event": "progress", "step": step, "message": message}
    if fraction is not None:
        line["fraction"] = round(max(0.0, min(1.0, fraction)), 3)
    sys.stderr.write(json.dumps(line) + "\n")
    sys.stderr.flush()


def version_tuple(text):
    return tuple(int(part) for part in text.split("."))


def at_least(have, want):
    have, want = version_tuple(have), version_tuple(want)
    width = max(len(have), len(want))
    return have + (0,) * (width - len(have)) >= want + (0,) * (width - len(want))


def run(argv):
    """(status, stdout and stderr together) of a short command."""
    try:
        done = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=300)
    except OSError as problem:
        raise Failure(f"could not run {argv[0]}: {problem.strerror}")
    except subprocess.TimeoutExpired:
        raise Failure(f"{os.path.basename(argv[0])} did not finish within 5 minutes")
    return done.returncode, done.stdout.decode("utf-8", errors="replace")


# -- release -------------------------------------------------------------------------------

def read_release(api, folder):
    """(version, asset name, download address, size or None) of the newest release."""
    event("release", "Looking for the newest AgentVM release")
    answer = os.path.join(folder, "release.json")
    child = subprocess.Popen(
        [CURL, "--silent", "--show-error", "--location", "--proto", "=https",
         "--proto-redir", "=https", "--max-time", "60",
         "--header", "Accept: application/vnd.github+json",
         "--output", answer, "--write-out", "%{http_code}", api],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = child.communicate()
    except KeyboardInterrupt:
        child.kill()
        child.wait()
        raise Canceled()
    code = out.decode("utf-8", errors="replace").strip()
    if child.returncode != 0:
        reason = err.decode("utf-8", errors="replace").strip() or f"curl status {child.returncode}"
        raise Failure(f"Could not reach GitHub to look for AgentVM releases: {reason}")
    if code == "404":
        raise Failure(f"No AgentVM release was found at {RELEASES_PAGE}: GitHub answered "
                      "\"not found\". The repository has no published release yet, or it is not public.")
    if code in ("403", "429"):
        raise Failure("GitHub refused to list AgentVM releases (HTTP " + code + "), most likely "
                      "because of its limit on requests. Try again later, or download the "
                      f"package from {RELEASES_PAGE}.")
    if code != "200":
        raise Failure(f"GitHub answered HTTP {code or '(none)'} when asked for the newest AgentVM release.")
    try:
        with open(answer, encoding="utf-8") as source:
            release = json.load(source)
    except (OSError, ValueError):
        raise Failure("GitHub's answer about the newest AgentVM release could not be read.")
    if not isinstance(release, dict):
        raise Failure("GitHub's answer about the newest AgentVM release could not be read.")
    tag = release.get("tag_name")
    version = tag[1:] if isinstance(tag, str) and tag.startswith("v") else tag
    if not isinstance(version, str) or not VERSION_PATTERN.fullmatch(version):
        raise Failure(f"The newest AgentVM release is tagged {tag!r}, which is not a version.")
    assets = release.get("assets")
    packages = [asset for asset in assets if isinstance(asset, dict)
                and isinstance(asset.get("name"), str) and asset["name"].endswith(".pkg")] \
        if isinstance(assets, list) else []
    if not packages:
        raise Failure(f"The AgentVM {version} release has no installer package (.pkg). "
                      f"See {RELEASES_PAGE}.")
    # agent-vm's packaging names it agent-vm_<version>.pkg; any other single package is taken too.
    named = [asset for asset in packages if asset["name"] == f"agent-vm_{version}.pkg"]
    if named:
        packages = named
    if len(packages) > 1:
        names = ", ".join(asset["name"] for asset in packages)
        raise Failure(f"The AgentVM {version} release has several installer packages ({names}), "
                      "and Cadabra cannot tell which one to install.")
    package = packages[0]
    name = package["name"]
    if "/" in name or name.startswith("."):
        raise Failure(f"The AgentVM {version} release names its package {name!r}, which is not a file name.")
    address = package.get("browser_download_url")
    if not isinstance(address, str) or not address.startswith("https://"):
        raise Failure(f"The AgentVM {version} release gives no https address for {name}.")
    size = package.get("size")
    return version, name, address, size if isinstance(size, int) and size > 0 else None


# -- download ------------------------------------------------------------------------------

def megabytes(count):
    return f"{count / 1_000_000:.1f} MB"


def download(address, path, size):
    name = os.path.basename(path)
    event("download", f"Downloading {name}", 0.0 if size else None)
    child = subprocess.Popen(
        [CURL, "--silent", "--show-error", "--fail", "--location", "--proto", "=https",
         "--proto-redir", "=https", "--speed-limit", "1000", "--speed-time", "60",
         "--output", path, address],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    last = -1.0
    try:
        while child.poll() is None:
            time.sleep(0.25)
            if size:
                try:
                    have = os.path.getsize(path)
                except OSError:
                    have = 0
                fraction = have / size
                if fraction - last >= 0.01:
                    last = fraction
                    event("download", f"Downloading {name} ({megabytes(have)} of {megabytes(size)})",
                          fraction)
    except KeyboardInterrupt:
        child.kill()
        child.wait()
        raise Canceled()
    err = child.stderr.read().decode("utf-8", errors="replace").strip()
    if child.returncode != 0:
        raise Failure(f"Could not download {name}: {err or f'curl status {child.returncode}'}")
    if not os.path.isfile(path):
        raise Failure(f"The download of {name} left no file.")
    if size and os.path.getsize(path) != size:
        raise Failure(f"The download of {name} is {os.path.getsize(path)} bytes, and GitHub "
                      f"lists it as {size}.")


# -- verify --------------------------------------------------------------------------------

def verify(path, team):
    name = os.path.basename(path)
    event("verify", f"Checking the signature of {name}")
    status, output = run([SPCTL, "--assess", "--type", "install", "--verbose", path])
    if status != 0 or "source=Notarized Developer ID" not in output:
        reason = " ".join(output.split()) or f"spctl status {status}"
        raise Failure(f"{name} is not notarized Developer ID software, so Cadabra does not "
                      f"install it ({reason}).")
    status, output = run([PKGUTIL, "--check-signature", path])
    if status != 0:
        raise Failure(f"The signature of {name} could not be checked: {' '.join(output.split())}")
    signers = [match.group(1) for match in map(SIGNER_PATTERN.match, output.splitlines()) if match]
    if not signers:
        raise Failure(f"{name} is not signed with a Developer ID Installer certificate, so "
                      "Cadabra does not install it.")
    if signers[0] != team:
        raise Failure(f"{name} is signed by the Developer ID team {signers[0]}, not AgentVM's "
                      f"({team}), so Cadabra does not install it.")


# -- install -------------------------------------------------------------------------------

def install(path, version):
    event("install", f"Waiting for Installer: follow its steps to install AgentVM {version}")
    # From here on a cancel is only noted: the package is Installer's until it quits (removing
    # it would pull it out from under an installation), and Installer has its own Cancel.
    asked = []
    signal.signal(signal.SIGINT, lambda _signum, _frame: asked.append(True))
    try:
        status, output = run_long([OPEN, "-W", "-b", INSTALLER_APP, path])
    finally:
        signal.signal(signal.SIGINT, signal.default_int_handler)
    if status != 0:
        raise Failure(f"Could not open {os.path.basename(path)} in Installer: "
                      f"{' '.join(output.split()) or f'open status {status}'}")


def run_long(argv):
    """(status, output) of a command that may wait for the user for as long as they take."""
    try:
        done = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)
    except OSError as problem:
        raise Failure(f"could not run {argv[0]}: {problem.strerror}")
    return done.returncode, done.stdout.decode("utf-8", errors="replace")


def check(link, version):
    event("check", "Checking the installed agent-vm")
    not_installed = (f"Installer closed, and AgentVM {version} is not installed: the "
                     "installation was canceled, or it failed (/var/log/install.log has the details).")
    if not (os.path.isfile(link) and os.access(link, os.X_OK)):
        raise Failure(f"{not_installed} There is no agent-vm at {link}.")
    status, output = run([link, "--version"])
    reported = output.strip().splitlines()[-1].strip() if output.strip() else ""
    if status != 0 or reported != version:
        raise Failure(f"{not_installed} {link} reports {reported or 'no version'} (status {status}).")


# -- main ----------------------------------------------------------------------------------

def install_newest(args):
    folder = tempfile.mkdtemp(prefix="cadabra-agentvm-install.")
    try:
        version, name, address, size = read_release(args.api, folder)
        if not at_least(version, args.min):
            raise Failure(f"The newest AgentVM release is {version}, and Cadabra needs "
                          f"{args.min} or later. Install a newer Cadabra, or wait for the "
                          f"AgentVM release at {RELEASES_PAGE}.")
        path = os.path.join(folder, name)
        download(address, path, size)
        verify(path, args.team)
        install(path, version)
        check(args.link, version)
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    event("done", f"Installed AgentVM {version}", 1.0)
    print(f"Installed AgentVM {version}: {args.link}")


def terminated(_signum, _frame):
    # A system shutdown (SIGTERM, which the job runner passes on): leave through the finally
    # clauses, so the temporary folder with the package goes too.
    sys.exit(143)


def main(argv):
    parser = argparse.ArgumentParser(prog="agentvm_install.py")
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("install")
    command.add_argument("--api", required=True)
    command.add_argument("--min", required=True)
    command.add_argument("--team", required=True)
    command.add_argument("--link", required=True)
    args = parser.parse_args(argv)
    signal.signal(signal.SIGTERM, terminated)
    if not VERSION_PATTERN.fullmatch(args.min):
        sys.stderr.write(f"Error: --min {args.min!r} is not a version.\n")
        return 2
    if not os.path.isabs(args.link):
        sys.stderr.write(f"Error: --link {args.link!r} is not an absolute path.\n")
        return 2
    try:
        install_newest(args)
    except (Canceled, KeyboardInterrupt):
        # A cancel during the install step is only noted (see install), so one that stops the
        # job always comes before it, or after it in the check, when the version is in place.
        sys.stderr.write("Error: Canceled.\n")
        return 130
    except Failure as problem:
        sys.stderr.write(f"Error: {problem}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
