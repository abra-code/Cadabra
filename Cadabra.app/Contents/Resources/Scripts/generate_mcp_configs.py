#!/usr/bin/env python3
# generate_mcp_configs.py
# Writes the session's mlx-agent --mcp-config JSON - {"servers":[{name,command,args,
# env?,gatedTools?}]} - plus the replay sandbox profile it references, both into the
# session dir. mlx-agent speaks MCP stdio directly, spawning each server with its
# command+args (the mcp-proxy HTTP shim of the WebUI era is gone from this app).
# Called by generate_stdio_mcp_config() in aichat.mcp.servers.library.sh.
#
# Usage: python3 generate_mcp_configs.py \
#            <out_json> <app_bundle> <tz> [<mcp_prefs_plist>]
#            [--box NAME --agent-vm PATH [--agent-vm-home DIR] --project DIR [--read-only]
#             --guest-tools DIR --guest-pycache DIR [--client mac|in-box]]
#            [--window-folders FILE]
#            [--all-servers]
#
# BOX MODE (--box): the servers run in an agent-vm box while the model stays on this Mac. Each
# server's command becomes `agent-vm exec --box NAME --project DIR [--read-only] [--env N=V ...]
# -- <server in the box> <args>`, so mlx-agent starts it in the box and talks to it over the
# exec's standard input and output. --guest-tools is where Cadabra's tools were copied in the
# box, in the layout of Cadabra.app/Contents (boxsession_tools_copy), and --guest-pycache the
# bytecode cache there. The servers follow the box pane's own settings (/servers/box, see
# mcp_box_setting), not this Mac's: the project is the only folder of this Mac the box sees, and
# the box's network rules, not Allow Network, decide what its programs reach:
#   - replay runs without its own sandbox by default (--no-sandbox, allowed "/" after the
#     project, which stays its working folder): the box is the boundary, and a folder replay's
#     profile would block could not be allowed during the session. With confineLocal on it
#     confines itself: --allow-write <project> and the box profile copied with it
#     (Resources/replay-box-sandbox.json), with the network the box allows;
#   - the time server needs no network; the search server runs with internet on (the box then
#     allows any public host, boxsession_tools_rules);
#   - pdfutil's roots are the project and the box's /private/tmp, and it is not --writable when
#     the project is shared read-only (its outputs could not be written anyway);
#   - the search server, the one Python server, gets PYTHONPATH and PYTHONPYCACHEPREFIX for the
#     copy, through --env, so they reach the program in the box rather than agent-vm on this Mac.
# --client in-box writes each server as a client inside the box starts it (its command and
# environment there, no agent-vm exec): for an external agent that runs in the box and starts
# the servers itself from its session/new mcpServers. The probe still runs through exec.
# --agent-vm-home, agent-vm's store when Cadabra uses another one, goes into each server's env,
# for agent-vm itself. Every exec of a window shares one project and mode, as agent-vm requires.
# The probe below runs each server exactly this way, so the box must be running.
#
# --all-servers is for the MCP Servers window, a catalog of every server and its tools: all four
# servers, whatever is turned on, each with its full set of tools (PDF editing included). The
# window follows no conversation, so no setting that chooses servers is read. The Local server
# still gets its sandbox profile from the settings, which does not change its tool list. No
# conversation is given this config.
#
# Almost all sandbox paths come from <mcp_prefs_plist>: the allow-network master
# gate, per-server enabled flags, the prominent project workspace, and the
# allowed-read / allowed-write lists shown and edited in the MCP servers dialog. When
# allow-network is false, the search server is omitted and replay gets --deny-network;
# the time server needs no network, so it follows only its own flag. The bundled pdf server (pdfutil) is network-free, so it honors only its
# own enabled flag (plus its own writable flag) and reuses the local sandbox's readable
# dirs as its --root confinement (see the pdf block below). That plist is seeded with Homebrew, nvm, temp, third-party tool/data
# dirs, and the app bundle by mcp_prefs_write_defaults() in aichat.library.sh, so
# nothing is granted to the sandbox invisibly here. The ticked SANDBOX PACKS
# (servers/local/packs, an array of pack ids; sandbox_packs.py) add their folders to the Local
# server's sandbox after the user's own paths. They do not widen the pdf server's roots: a pack
# is for tools that build, not for reading documents. (The system executable dirs and
# macOS system libraries are granted by replay's sandbox baseline and are deliberately
# absent, as is the app bundle — replay self-sandboxes at startup and the local server
# has no playlist to re-read, so nothing under the bundle is read once the sandbox is
# live.)
#
# The one sandbox path NOT taken from the plist is the per-login-session temp dir
# ($TMPDIR): it is granted read-write fresh from the environment on every launch (see
# the local block). Its random /var/folders value differs per user login session and
# would go stale if stored, so only the on/off decision lives in the plist
# (servers/local/include-session-tmpdir, default on); the path itself is recomputed.

import argparse
import concurrent.futures
import fcntl
import hashlib
import json
import os
import plistlib
import selectors
import signal
import subprocess
import sys
import time

out_json        = sys.argv[1]
app_bundle      = sys.argv[2]
tz              = sys.argv[3]
mcp_prefs_plist = sys.argv[4] if len(sys.argv) > 4 and not sys.argv[4].startswith("--") else ""

# The box options, after the positional arguments; parsed below, once any prior config is gone.
_box_words = sys.argv[5:] if mcp_prefs_plist else sys.argv[4:]

# Everything (the config and the replay sandbox profile) lands in the session dir.
session_dir = os.path.dirname(os.path.abspath(out_json))

# Remove any prior config HERE, before anything that can raise - not merely before the
# probe. Everything below is fallible (prefs parsing, makedirs, writing the sandbox
# profile, then the probe itself), and the shell caller does not check this script's
# exit code. So an exception at any point must degrade to "no config found" - the
# transport builder then falls back to chat mode - rather than leaving the previous
# launch's file in place, carrying the previous launch's roots, --writable state and
# gated tool list. A stale config is not a cosmetic problem: it would silently outlive
# every prefs change the user makes, including revoking write access.
out_abs = os.path.abspath(out_json)
os.makedirs(os.path.dirname(out_abs), exist_ok=True)
if os.path.exists(out_abs):
    os.remove(out_abs)

# sandbox_packs.py is beside this file. Imported here, after the prior config is gone, like
# everything else that can fail. No bytecode for it: a cache folder written into the
# application would break its signature.
sys.dont_write_bytecode = True
import sandbox_packs

# No abbreviations: "--read" must not quietly mean --read-only. Bad options end the script with
# no config, which the transport builder reads as a chat with no tools - never as tools on this
# Mac for a window whose tools were meant to run in a box.
_box_parser = argparse.ArgumentParser(prog="generate_mcp_configs.py", add_help=False, allow_abbrev=False)
_box_parser.add_argument("--box", default="")
_box_parser.add_argument("--agent-vm", default="")
_box_parser.add_argument("--agent-vm-home", default="")
_box_parser.add_argument("--project", default="")
_box_parser.add_argument("--read-only", action="store_true")
_box_parser.add_argument("--guest-tools", default="")
_box_parser.add_argument("--guest-pycache", default="")
_box_parser.add_argument("--client", default="mac", choices=("mac", "in-box"))
_box_parser.add_argument("--window-folders", default="")
_box_parser.add_argument("--all-servers", action="store_true")
box = _box_parser.parse_args(_box_words)
# --window-folders FILE is the one option of a window whose tools run on this Mac, and it
# comes alone: a box sees one folder of this Mac, its project, fixed when the box starts.
if box.window_folders:
    if len(_box_words) != 2:
        sys.exit("generate_mcp_configs: --window-folders cannot be combined with box options")
    if not box.window_folders.startswith("/"):
        sys.exit("generate_mcp_configs: --window-folders must be an absolute path")
elif box.all_servers:
    if len(_box_words) != 1:
        sys.exit("generate_mcp_configs: --all-servers cannot be combined with other options")
elif _box_words and not box.box:
    sys.exit("generate_mcp_configs: box options need --box")
if box.box:
    for _name, _value in (("--agent-vm", box.agent_vm), ("--project", box.project),
                          ("--guest-tools", box.guest_tools), ("--guest-pycache", box.guest_pycache)):
        if not _value.startswith("/"):
            sys.exit(f"generate_mcp_configs: {_name} must be an absolute path in box mode")
    if box.agent_vm_home and not box.agent_vm_home.startswith("/"):
        sys.exit("generate_mcp_configs: --agent-vm-home must be an absolute path")

packages_dir = f"{app_bundle}/Contents/Library/Packages"
python3_bin  = f"{app_bundle}/Contents/Library/Python/bin/python3"
replay_bin   = f"{app_bundle}/Contents/Support/replay"
time_bin     = f"{app_bundle}/Contents/Support/time-mcp"

# ── Load user preferences (if any) ────────────────────────────────────────────
prefs = {}
if mcp_prefs_plist and os.path.isfile(mcp_prefs_plist):
    try:
        with open(mcp_prefs_plist, "rb") as fh:
            prefs = plistlib.load(fh)
    except Exception as e:
        print(f"  warning: could not read MCP prefs ({e}); using defaults")

# ── The window's own folders (--window-folders) ──────────────────────────────
# Folders the user allowed for one chat window while its conversation ran, on top of the
# settings: {"read_only": [...], "read_write": [...]}. The file is Cadabra's own, written only
# from the window's folder chooser. A file that is given but cannot be read ends the script with
# no config: leaving the folders out would restart the servers without what the user allowed.
window_read_only = []
window_read_write = []
if box.window_folders:
    try:
        with open(box.window_folders, "r", encoding="utf-8") as fh:
            _window = json.load(fh)
        if not isinstance(_window, dict):
            raise ValueError("not an object")
        # Read-only first: a folder in both lists (the applet never writes one so) is read-only.
        for _key, _into in (("read_only", window_read_only), ("read_write", window_read_write)):
            for _folder in _window.get(_key) or []:
                if not isinstance(_folder, str) or not _folder.startswith("/"):
                    raise ValueError(f"{_key} holds something that is not an absolute path")
                # The user allowed a real folder, checked against the folders that are never
                # allowed. A path that has since become a link (or passes through one), or is
                # no longer a folder, is left out: replay and pdfutil follow links, so a tool
                # that can write beside the folder could otherwise point it anywhere.
                if os.path.realpath(_folder) != _folder or not os.path.isdir(_folder):
                    print(f"  warning: the window's folder {_folder!r} is no longer the folder that was allowed; leaving it out")
                    continue
                if _folder not in window_read_write and _folder not in window_read_only:
                    _into.append(_folder)
    except (OSError, ValueError) as e:
        sys.exit(f"generate_mcp_configs: cannot read --window-folders {box.window_folders}: {e}")

def srv_enabled(name: str) -> bool:
    return prefs.get("servers", {}).get(name, {}).get("enabled", True)

def srv_flag(name: str, key: str, default: bool = True) -> bool:
    return prefs.get("servers", {}).get(name, {}).get(key, default)

# The box pane's settings (/servers/box/<name>): a bool, or the name's default for anything else,
# as mcp_box_setting reads them.
BOX_DEFAULTS = {"local": True, "confineLocal": False, "pdf": True, "pdfWritable": True,
                "time": True, "internet": False}

def box_flag(name: str) -> bool:
    box_prefs = prefs.get("servers", {}).get("box")
    value = box_prefs.get(name) if isinstance(box_prefs, dict) else None
    return value if isinstance(value, bool) else BOX_DEFAULTS[name]

# Master network gate. When false, the search server (the one that uses the network) is not
# started and the local (replay) server runs with --deny-network. The time server reads only the
# clock and the time zone data, so it does not depend on it.
allow_network = prefs.get("allow-network", True)

def mac_server_on(name: str) -> bool:
    """Whether a server is started on this Mac: its own setting, or every server with
    --all-servers."""
    if box.box:
        return False
    if box.all_servers:
        return True
    if name == "search":
        return allow_network and srv_enabled("search")
    return srv_enabled(name)

# ── Build the per-server config table, honoring enabled flags ─────────────────
servers = {}           # short name -> {command, args, env?}
server_order = []      # short names in launch order
user_project = ""      # set in the local block; pre-init so it's always defined

if mac_server_on("local"):
    local_prefs = prefs.get("servers", {}).get("local", {})
    # ── replay sandbox paths ──────────────────────────────────────────────────
    # Every extra sandbox path is taken from the user-managed prefs (shown and
    # editable in the MCP servers dialog), except the per-login-session $TMPDIR
    # added read-write below, which is computed fresh each launch rather than
    # persisted. The prefs plist is seeded with Homebrew, nvm, temp, and
    # third-party tool/data dirs by mcp_prefs_write_defaults() in
    # aichat.library.sh — nothing else is added to the sandbox here. (replay's
    # sandbox baseline separately grants exec
    # of /bin, /usr/bin, /sbin, /usr/sbin and loading of system libraries under
    # /usr/lib and /System/Library; the app bundle is not needed because replay
    # self-sandboxes at startup and the local server has no playlist to re-read.)
    allowed_read = [directory for directory in (local_prefs.get("allowed-read") or []) if directory]
    allowed_read += [directory for directory in window_read_only if directory not in allowed_read]
    # The ticked sandbox packs: their folders, and their single files to read, after the user's
    # own. User packs are beside the settings file. A pack that is invalid or not installed
    # grants nothing and says so in the log.
    pack_read_only, pack_read_write, pack_files, pack_messages = sandbox_packs.grants(
        local_prefs.get(sandbox_packs.PREFS_KEY),
        app_bundle,
        os.path.join(os.path.dirname(os.path.abspath(mcp_prefs_plist)), sandbox_packs.USER_DIR_NAME) if mcp_prefs_plist else "",
        (local_prefs.get("project") or "").strip())
    for _message in pack_messages:
        print(f"  warning: {_message}")
    allowed_read += [path for path in pack_read_only + pack_files if path not in allowed_read]

    # Project workspace: the prominent read-write directory chosen by the user.
    # It is passed as the single explicit --allow-write so replay treats it as the
    # project (working) directory: the first entry of list_allowed_directories and
    # the base that grep_files resolves relative globs against when a call omits
    # `directory`.
    user_project = (local_prefs.get("project") or "").strip()

    # Every other directory travels in a generated --sandbox-profile JSON instead
    # of a long --allow-read/--allow-write command line. As of replay 2.1 a
    # profile's read_only/read_write dirs are also folded into the MCP allowed-dir
    # list (list_allowed_directories and the write_file/read_file path checks), so
    # the soft MCP path layer stays in sync with the kernel sandbox either way.
    # additional read-write dirs (everything the user added beyond the project):
    profile_read_write = []
    for directory in (local_prefs.get("allowed-write") or []) + window_read_write + pack_read_write:
        if directory and directory != user_project and directory not in profile_read_write:
            profile_read_write.append(directory)
    # Per-login-session temp dir ($TMPDIR, e.g. /var/folders/xx/.../T): granted
    # read-write so sandboxed shell tools can use the login session's own scratch
    # dir. The path itself is recomputed from the environment on every launch and
    # deliberately NOT read from / written to the prefs plist — its random
    # /var/folders value differs per user login session, so a persisted copy would go
    # stale. Only the user's decision is stored, in include-session-tmpdir (default
    # on, absent == on); the dialog shows the temp dir as a removable row that toggles
    # that flag. realpath() resolves the /var -> /private/var symlink to the canonical
    # path the kernel sandbox and the MCP soft path checks compare against (the same
    # reason the seeded write path is /private/tmp, not /tmp).
    include_session_tmpdir = local_prefs.get("include-session-tmpdir", True)
    session_tmpdir = os.environ.get("TMPDIR", "").strip()
    if include_session_tmpdir and session_tmpdir:
        session_tmpdir = os.path.realpath(session_tmpdir)
        if (os.path.isdir(session_tmpdir)
                and session_tmpdir != user_project
                and session_tmpdir not in profile_read_write):
            profile_read_write.append(session_tmpdir)
    # read-only dirs all live in the profile (drop any also granted read-write):
    profile_read_only = [directory for directory in allowed_read if directory not in profile_read_write]
    # The system's own programs can be run under replay's sandbox without any grant, but their
    # folders cannot be listed or read, and tools that look for another program do both: cmake
    # crashes when it cannot list /usr/bin. They hold nothing but what macOS ships, so they are
    # always readable; the dialog says so beside its tables.
    profile_read_only += [directory for directory in sandbox_packs.SYSTEM_PROGRAM_FOLDERS
                          if directory not in profile_read_only and directory not in profile_read_write]

    replay_args = ["--mcp-server"]
    if not allow_network:
        replay_args.append("--deny-network")
    if user_project:
        replay_args += ["--allow-write", user_project]

    # Write the sandbox profile next to the config and point replay at it.
    # allow_network is intentionally omitted from the JSON: in MCP mode the CLI
    # --deny-network gate is authoritative (replay overrides the profile's network
    # setting), and import_baseline / allow_exec / allow_fork keep their permissive
    # defaults so the Local server can still spawn shells and load system libraries.
    # replay reads this file at startup, before it self-sandboxes, so it does not
    # need to be inside any granted directory.
    if profile_read_only or profile_read_write:
        os.makedirs(session_dir, exist_ok=True)
        sandbox_profile = {}
        if profile_read_only:
            sandbox_profile["read_only"] = profile_read_only
        if profile_read_write:
            sandbox_profile["read_write"] = profile_read_write
        profile_text = json.dumps(sandbox_profile, indent=2)
        # For a window with a list of its own (even an empty one: the window's sandbox packs
        # were changed during its conversation) the profile gets a name of its own, from its
        # content: mlx-agent restarts a server on a reload only when its command line changed,
        # and replay reads the profile once, at its start. It also leaves the profile a running
        # session's replay may still be about to read untouched until the new config replaces
        # the old.
        profile_name = "mcp-replay-sandbox.json"
        if box.window_folders:
            profile_name = "mcp-replay-sandbox-%s.json" % hashlib.sha256(profile_text.encode("utf-8")).hexdigest()[:12]
        sandbox_profile_path = os.path.join(session_dir, profile_name)
        with open(sandbox_profile_path, "w") as profile_file:
            profile_file.write(profile_text)
        replay_args += ["--sandbox-profile", sandbox_profile_path]

    servers["local"] = {
        "command": replay_bin,
        "args": replay_args,
    }
    server_order.append("local")

if mac_server_on("pdf"):
    # pdfutil (github.com/abra-code/pdfutil, Apache 2.0): a network-free PDF server
    # exposing pdf_info / pdf_text / pdf_search / pdf_outline / pdf_render / pdf_ocr /
    # pdf_forms_list / pdf_list over MCP stdio, plus the mutating tier below when
    # writable. It confines every tool to its --root directories and requires at least
    # one, so it is granted the SAME directory set the local (replay) sandbox may touch:
    # the project workspace, the user's extra read/write paths, and the login-session
    # $TMPDIR. Those are read from the local prefs directly so PDF access does not depend
    # on the "local" server being enabled. pdfutil has no network, so it is NOT gated by
    # allow-network.
    pdfutil_bin = f"{app_bundle}/Contents/Support/pdfutil"
    pdf_local_prefs = prefs.get("servers", {}).get("local", {})
    # servers/pdf/writable adds --writable, which serves pdfutil's mutating tier. Default
    # on, matching the other bundled servers (and strictly milder than what the Local
    # server already grants by default: pdfutil's outputs are CREATE-ONLY - a new file
    # under a --root, refused if anything already exists there, with no overwrite
    # parameter - so a mutating call can add a PDF but can never modify or destroy an
    # existing file, in either the read-write or the read-only path list). Which of its
    # tools end up gated is not decided here: pdfutil annotates every tool with
    # readOnlyHint, and the emit step below reads those hints off the live server.
    pdf_writable = srv_flag("pdf", "writable", True)
    if box.all_servers:
        pdf_writable = True
    pdf_roots = []

    def _add_pdf_root(directory):
        directory = (directory or "").strip()
        if not directory:
            return
        # pdfutil canonicalizes its roots (resolvingSymlinksInPath); realpath here so
        # the /var -> /private/var (and /tmp -> /private/tmp) symlinks match, and so
        # duplicates collapse. pdfutil rejects a --root that is not an existing dir, so
        # skip anything that no longer exists rather than start a server that exits 1.
        directory = os.path.realpath(directory)
        if os.path.isdir(directory) and directory not in pdf_roots:
            pdf_roots.append(directory)

    _add_pdf_root(pdf_local_prefs.get("project"))
    for directory in (pdf_local_prefs.get("allowed-write") or []):
        _add_pdf_root(directory)
    for directory in (pdf_local_prefs.get("allowed-read") or []):
        _add_pdf_root(directory)
    for directory in window_read_write + window_read_only:
        _add_pdf_root(directory)
    if pdf_local_prefs.get("include-session-tmpdir", True):
        _add_pdf_root(os.environ.get("TMPDIR", ""))

    # pdfutil requires >=1 existing --root and refuses to start otherwise. If the user
    # has cleared every sandbox path (empty project, no read/write paths, session tmpdir
    # off) there is nothing for it to read, so the server is simply omitted rather than
    # started against a fallback like $HOME - that would grant the PDF tools read access
    # to the whole home dir in exactly the configuration where the user asked for none,
    # and would also give pdf a broader set than replay. With no roots the toggle has
    # nothing to act on; enabling it takes effect again as soon as a sandbox path exists.
    if box.all_servers and not pdf_roots:
        # Only the tool list is wanted, and the server does not start without a folder.
        pdf_roots = ["/private/tmp"]
    if pdf_roots:
        pdf_args = ["mcp"]
        for root in pdf_roots:
            pdf_args += ["--root", root]
        if pdf_writable:
            pdf_args.append("--writable")
        servers["pdf"] = {
            "command": pdfutil_bin,
            "args": pdf_args,
        }
        server_order.append("pdf")
    else:
        print("  pdf server enabled but no readable sandbox paths configured; omitting it")

# The time server is a native program (time-mcp): it reads the clock and the system's time zone
# files, uses no network and writes nothing. --local-timezone is the zone its tool descriptions
# suggest when the user names none; in a box it is this Mac's zone, not the box's own.
if mac_server_on("time"):
    servers["time"] = {
        "command": time_bin,
        "args": ["--local-timezone", tz],
    }
    server_order.append("time")

# -P for the `python3 -m` server, here and in a box: without it Python puts the working folder
# first on sys.path, ahead of PYTHONPATH and its own library, and the server runs in the project
# folder. A file there named like a module it imports (argparse.py, a duckduckgo_mcp_server
# folder) would then run on this Mac, outside every sandbox, the next time a window starts its
# tools: code left in the project by an earlier session, or shipped in a folder someone else made.
if mac_server_on("search"):
    servers["search"] = {
        "command": python3_bin,
        "args": ["-P", "-m", "duckduckgo_mcp_server.server"],
        "env": {"PYTHONPATH": packages_dir},
    }
    server_order.append("search")

# -- Box mode: the same servers, run in the box through agent-vm exec -------------
# See BOX MODE at the top. The guest paths mirror Cadabra.app/Contents under --guest-tools.
if box.box:
    user_project = box.project
    guest_python = f"{box.guest_tools}/Library/Python/bin/python3"
    guest_python_env = {"PYTHONPATH": f"{box.guest_tools}/Library/Packages",
                        "PYTHONPYCACHEPREFIX": box.guest_pycache}

    def boxed(argv, guest_env=None):
        """One server spec: agent-vm exec into the box, the guest environment through --env."""
        args = ["exec", "--box", box.box, "--project", box.project]
        if box.read_only:
            args.append("--read-only")
        for name, value in sorted((guest_env or {}).items()):
            args += ["--env", f"{name}={value}"]
        spec = {"command": box.agent_vm, "args": args + ["--"] + argv,
                # The server as a client inside the box starts it (--client in-box).
                "guest": {"command": argv[0], "args": argv[1:], "env": dict(guest_env or {})}}
        if box.agent_vm_home:
            spec["env"] = {"AGENT_VM_HOME": box.agent_vm_home}
        return spec

    if box_flag("local"):
        replay_argv = [f"{box.guest_tools}/Support/replay", "--mcp-server"]
        if box_flag("confineLocal"):
            replay_argv += ["--allow-write", box.project,
                            "--sandbox-profile", f"{box.guest_tools}/Resources/replay-box-sandbox.json"]
        else:
            replay_argv += ["--no-sandbox", "--allow-write", box.project, "--allow-write", "/"]
        servers["local"] = boxed(replay_argv)
        server_order.append("local")
    if box_flag("pdf"):
        pdf_argv = [f"{box.guest_tools}/Support/pdfutil", "mcp",
                    "--root", box.project, "--root", "/private/tmp"]
        if box_flag("pdfWritable") and not box.read_only:
            pdf_argv.append("--writable")
        servers["pdf"] = boxed(pdf_argv)
        server_order.append("pdf")
    if box_flag("time"):
        servers["time"] = boxed([f"{box.guest_tools}/Support/time-mcp", "--local-timezone", tz])
        server_order.append("time")
    if box_flag("internet"):
        servers["search"] = boxed([guest_python, "-P", "-m", "duckduckgo_mcp_server.server"],
                                  guest_python_env)
        server_order.append("search")

# ── Ask each server which of its tools need a permission prompt ───────────────
# gatedTools lists the tools that require a session/request_permission round-trip
# before mlx-agent dispatches them. The list is ASKED OF EACH SERVER, never written
# down here: a server is started once with the exact command line it will run with,
# handshaken, and its tools/list reply read. Hardcoding tool names rots silently -
# a server that gains a mutating tool ships it un-gated until someone remembers to
# edit this file, which is exactly how pdfutil's pdf_render_to_file went unprompted.
#
# The rule is fail-closed: a tool is gated unless it positively declares MCP's
# readOnlyHint: true. An unannotated server (no hints at all) therefore has every
# tool gated - "I don't know" is treated as "ask the user", never as "safe". The
# cost of a server being honest about its read-only tools is one annotation; the
# cost of guessing wrong is an unprompted write.
# Probe the servers from the working directory they will actually run in. ChatView
# launches mlx-agent with the Project workspace as cwd (falling back to $HOME for a
# value that is not absolute-and-existing) and the servers inherit it, so the probe
# runs where they will. (The `python3 -m` server no longer imports from that
# folder: see -P above.)
#
# Read the pref directly rather than reusing user_project: that one is only set when
# the LOCAL server is enabled and is .strip()ed, while the launcher reads this pref
# unconditionally and does not strip it (aichat.mcp.servers.library.sh). Reproducing
# the launcher's rule exactly is the whole point - a probe that runs somewhere the
# servers will not is worse than no probe, because it describes the wrong module
# confidently.
probe_project = prefs.get("servers", {}).get("local", {}).get("project") or ""
probe_cwd = probe_project if (probe_project.startswith("/") and os.path.isdir(probe_project)) \
    else os.path.expanduser("~")
# In a box the agent's cwd is the box's project (aichat_acp_transport_json), and the servers'
# own working folder is set in the box by agent-vm, so the probe runs from the same place.
if box.box and os.path.isdir(box.project):
    probe_cwd = box.project

# Everything below decides a security policy from a server's own answer, so the
# parsing is strict on purpose: anything unexpected fails the probe (and drops the
# server) rather than producing a half-trusted list. The probe reads until the
# reply arrives instead of waiting for the process to exit - a server is not
# obliged to quit when its stdin closes, and one that lingers must not cost a
# 15-second stall (or, worse, be mistaken for a server that never answered).
MCP_PROBE_DEADLINE = 10.0     # seconds for the whole handshake, not per read
MCP_PROBE_MAX_PAGES = 20      # tools/list is paginated; bound the cursor loop
MCP_PROBE_MAX_CURSOR = 4096   # a pagination cursor is opaque, but it is echoed back
MCP_PROBE_MAX_BUFFER = 4 << 20
MCP_PROBE_MAX_TOOLS = 2000

def _probe_fail(name, reason):
    print(f"  warning: {name} did not describe itself ({reason!r})")
    return None

def _send(stream, message, deadline):
    """Write one JSON-RPC message, refusing to outlive the probe deadline.

    A server that never drains its stdin must not be able to wedge the window-launch
    path, so the write is bounded like every read is.

    The fd MUST be made non-blocking for this to hold, and select() alone is not
    enough. select() reports a pipe writable when as little as PIPE_BUF is free, but
    a blocking write(fd, n) only returns once ALL n bytes are gone - so a large-enough
    write sails past the select() guard and then blocks forever with no deadline to
    save it. Nor do the size caps save us: MCP_PROBE_MAX_CURSOR * MCP_PROBE_MAX_PAGES
    is ~84 KB of echoed cursors, comfortably more than a 64 KB pipe, so a server that
    paginates while refusing to read gets there in about 17 pages. Non-blocking turns
    that into a partial write plus BlockingIOError, which the loop can time out on.
    """
    payload = (json.dumps(message) + "\n").encode("utf-8")
    fd = stream.fileno()
    selector = selectors.DefaultSelector()
    selector.register(stream, selectors.EVENT_WRITE)
    original_flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, original_flags | os.O_NONBLOCK)
    try:
        while payload:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise TimeoutError("timed out writing to the server")
            try:
                payload = payload[os.write(fd, payload):]
            except BlockingIOError:
                continue  # select() lied about how much room there was; re-arm
    finally:
        # Restore before handing the fd back: the caller may close() it, and leaving
        # O_NONBLOCK on a shared description is the kind of thing that bites elsewhere.
        try:
            fcntl.fcntl(fd, fcntl.F_SETFL, original_flags)
        except OSError:
            pass
        selector.close()

def _json_lines(stream, deadline):
    """Yield JSON objects from a line-delimited stream until the deadline passes.

    Reads bytes and decodes with errors="replace" so one undecodable byte in a
    startup banner costs that line, not the whole probe, and splits on "\\n" only
    - str.splitlines() also breaks on U+2028/U+2029/U+0085, which are legal raw
    characters inside a JSON string and which Swift's JSONEncoder emits unescaped.
    Splitting before decoding is what makes that safe: no multibyte sequence can
    contain 0x0A. A top-level array is a JSON-RPC batch, which the 2025-03-26
    revision this probe negotiates still permits.
    """
    selector = selectors.DefaultSelector()
    selector.register(stream, selectors.EVENT_READ)
    buffered = b""
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                return
            chunk = stream.read1(65536)
            if not chunk:
                return                      # EOF: the server closed stdout
            buffered += chunk
            if len(buffered) > MCP_PROBE_MAX_BUFFER:
                return                      # a newline-free flood, not a reply
            while b"\n" in buffered:
                raw, buffered = buffered.split(b"\n", 1)
                text = raw.decode("utf-8", errors="replace").strip().lstrip("﻿")
                if not (text.startswith("{") or text.startswith("[")):
                    continue                # banners and progress chatter
                try:
                    message = json.loads(text)
                except ValueError:
                    continue
                for item in (message if isinstance(message, list) else [message]):
                    if isinstance(item, dict):
                        yield item
    finally:
        selector.close()

def _await_result(replies, request_id):
    """Return the result object for one request id, or None.

    Matches on a RESPONSE, not merely on an id: JSON-RPC id spaces are per-direction,
    so a server's own request may legitimately carry the same id we just used, and a
    request carries "method" where a response carries "result" or "error".
    """
    for message in replies:
        if message.get("id") != request_id or "method" in message:
            continue
        result = message.get("result")
        return result if isinstance(result, dict) else None
    return None

def probe_tools(name, spec):
    """Ask a server to describe itself. Returns its tools, or None on any doubt."""
    env = os.environ.copy()
    env.update(spec.get("env") or {})
    try:
        # start_new_session so the whole process group can be cleaned up: killing
        # the direct child alone leaks any helper it forked holding the pipe.
        # stderr is discarded rather than piped - nothing reads it during the
        # probe, and a server that fills a 64K stderr pipe would deadlock.
        proc = subprocess.Popen([spec["command"]] + list(spec.get("args") or []),
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, env=env, cwd=probe_cwd,
                                start_new_session=True)
    except Exception as e:
        return _probe_fail(name, e)

    deadline = time.monotonic() + MCP_PROBE_DEADLINE
    try:
        replies = _json_lines(proc.stdout, deadline)
        # protocolVersion 2025-03-26 is the revision that defines tool annotations;
        # asking for it is what entitles this probe to read readOnlyHint.
        _send(proc.stdin, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {"name": "cadabra-config", "version": "1"}}}, deadline)
        _send(proc.stdin,
              {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}, deadline)
        if _await_result(replies, 1) is None:
            return _probe_fail(name, "no reply to initialize")

        tools = []
        cursor = None
        for page in range(MCP_PROBE_MAX_PAGES):
            request_id = 2 + page
            params = {"cursor": cursor} if cursor else {}
            _send(proc.stdin, {"jsonrpc": "2.0", "id": request_id,
                               "method": "tools/list", "params": params}, deadline)
            result = _await_result(replies, request_id)
            if result is None:
                return _probe_fail(name, "no usable reply to tools/list")
            page_tools = result.get("tools")
            if not isinstance(page_tools, list):
                return _probe_fail(name, "tools/list reply has no tools array")
            tools += page_tools
            if len(tools) > MCP_PROBE_MAX_TOOLS:
                return _probe_fail(name, f"advertised more than {MCP_PROBE_MAX_TOOLS} tools")
            # Absent means "last page". Anything else present but unusable is a
            # malformed reply, and stopping early there would silently accept a
            # TRUNCATED list - whose missing tools would then be un-gated, because
            # gatedTools is an allowlist by omission.
            cursor = result.get("nextCursor")
            if cursor is None:
                break
            if not isinstance(cursor, str) or not cursor or len(cursor) > MCP_PROBE_MAX_CURSOR:
                return _probe_fail(name, "unusable nextCursor")
        else:
            return _probe_fail(name, f"still paginating after {MCP_PROBE_MAX_PAGES} pages")
    except Exception as e:
        return _probe_fail(name, e)
    finally:
        # Shut down the way the MCP spec asks: close stdin and give the server a
        # moment to exit on its own EOF, then escalate. The waits are short because
        # this sits on the window-launch path - four stubborn servers must not add
        # up to a visible stall.
        for closer in (lambda: proc.stdin.close(), lambda: proc.stdout.close(),
                       lambda: proc.wait(timeout=0.3),
                       lambda: os.killpg(proc.pid, signal.SIGTERM),
                       lambda: proc.wait(timeout=0.5)):
            try:
                closer()
            except Exception:
                pass
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except Exception:
                pass

    # Validate before any of it reaches a gating decision. A tool whose name is not
    # a usable string is fatal for the WHOLE server: mlx-agent parses gatedTools as
    # [String] and one non-string element makes that cast fail wholesale, silently
    # un-gating every tool the server has.
    if not tools:
        return _probe_fail(name, "advertised no tools")
    for tool in tools:
        if not isinstance(tool, dict):
            return _probe_fail(name, "a tools/list entry is not an object")
        if not isinstance(tool.get("name"), str) or not tool["name"]:
            return _probe_fail(name, "a tool has no usable name")
        if tool.get("annotations") is not None and not isinstance(tool["annotations"], dict):
            return _probe_fail(name, f"tool {tool['name']} has malformed annotations")
    return tools

# ── Emit the mlx-agent --mcp-config JSON ──────────────────────────────────────
# {"servers":[{name,command,args,env?,gatedTools?}]} from the servers constructed
# above. A server that will not describe itself is omitted rather than written out
# un-gated: it could not have served those tools anyway, and a config entry with no
# gatedTools is indistinguishable from one whose tools are all genuinely read-only.
# (Any prior config was already removed up at session_dir, before the first fallible
# step, so there is nothing stale left to outlive a crash here.)

def _safe_probe(name):
    try:
        return probe_tools(name, servers[name])
    except Exception as e:                  # a probe must never take the config down
        return _probe_fail(name, e)

# Probe concurrently: the servers are independent processes, and serially a stalled
# one costs its full deadline before the next even starts - four of them would put
# ~40s in front of a chat window that cannot open until this file exists. Fanned out,
# the worst case is one deadline. Results are consumed in server_order below, so the
# emitted config stays deterministic even though the warnings may interleave.
with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(server_order))) as pool:
    probed = dict(zip(server_order, pool.map(_safe_probe, server_order)))

stdio_servers = []
for name in server_order:
    spec = servers[name]
    tools = probed[name]
    if tools is None:
        print(f"  omitting the {name} server from this session's config")
        continue
    if box.box and box.client == "in-box":
        # For a client that runs in the box itself (an external agent there): the server's own
        # command line and environment in the box, no agent-vm exec. Probed above as mlx-agent
        # would run it, through exec, since the probe runs on this Mac.
        guest = spec["guest"]
        entry = {"name": name, "command": guest["command"], "args": list(guest["args"])}
        if guest["env"]:
            entry["env"] = guest["env"]
    else:
        entry = {"name": name, "command": spec["command"], "args": list(spec.get("args") or [])}
        if spec.get("env"):
            entry["env"] = spec["env"]
    gated = list(dict.fromkeys(          # de-duplicated, order preserved
        tool["name"] for tool in tools
        if (tool.get("annotations") or {}).get("readOnlyHint") is not True))
    if gated:
        entry["gatedTools"] = gated
    print(f"  {name}: {len(tools)} tool(s), {len(gated)} permission-gated")
    stdio_servers.append(entry)
with open(out_abs, "w") as fh:
    json.dump({"servers": stdio_servers}, fh, indent=2)
print(f"  wrote mcp config {out_json} ({len(stdio_servers)} server(s))")
if user_project:
    print(f"  project workspace: {user_project}")
