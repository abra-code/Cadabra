#!/usr/bin/env python3
"""The sandbox profiles the model engines run under.

    inference_sandbox.py llama --engine-dir DIR --model FILE --port N --out FILE

mlx-agent's own profile (agent_profile below) is built by acp_transport_json.py, which imports
this file.

llama-server is third-party code that parses a model file and serves one port. Its profile, in
Seatbelt's policy language for /usr/bin/sandbox-exec, lets it:
- read and run its own folder (the server and its libraries);
- read the model file, under the path it was given and under its real path (a Hugging Face
  snapshot entry is a link into the repository's blobs folder), and the other parts of a model
  split into several files;
- use the GPU: the two driver connections Metal opens on Apple silicon, Metal's three cache
  folders, and leave to hand its separate compiler service access to those caches and to the
  engine's folder;
- listen on its port of this Mac.
Nothing else: no outgoing connection, no other program, no write outside Metal's caches.

The profile is written whole, with every path in it, rather than passed as parameters: the
caller is a shell script and a path is the user's (quotes, spaces).

Exit status 0 with the profile written; 1 with a message on stderr and no file.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.parse

GPU_USER_CLIENTS = ("AGXDeviceUserClient", "IOSurfaceRootUserClient")
GPU_CACHE_FOLDERS = ("com.apple.metal", "com.apple.metalfe", "com.apple.gpuarchiver")
# "name-00001-of-00003.gguf": llama.cpp opens the other parts itself, from the first one's folder.
SPLIT_PART = re.compile(r"^(?P<stem>.*)-\d{5}-of-(?P<count>\d{5})\.gguf$")


def quoted(text):
    """A string literal in Seatbelt's language (a Scheme string)."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def regex_quoted(text):
    """Text matched literally inside a Seatbelt regular expression."""
    return re.sub(r"([\\.^$*+?()\[\]{}|])", r"\\\1", text)


def user_cache_dir():
    """The per-user cache folder (under /private/var/folders), as a real path, or ''."""
    try:
        out = subprocess.run(["/usr/bin/getconf", "DARWIN_USER_CACHE_DIR"], capture_output=True,
                             text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""
    return os.path.realpath(out) if out else ""


def gpu_rules(engine_dir, cache_dir):
    """What Metal needs, for an engine whose shader code is in engine_dir."""
    caches = [cache_dir.rstrip("/") + "/" + name for name in GPU_CACHE_FOLDERS] if cache_dir else []
    lines = ["; the GPU",
             "(allow iokit-open-user-client (iokit-user-client-class %s))"
             % " ".join(quoted(name) for name in GPU_USER_CLIENTS),
             "(allow syscall-mig)",
             "(allow system-info)",
             '(allow user-preference-read (preference-domain "kCFPreferencesAnyApplication"))',
             '(allow file-issue-extension (require-all (extension-class "com.apple.app-sandbox.read") '
             "(subpath %s)))" % quoted(engine_dir)]
    if caches:
        paths = " ".join("(subpath %s)" % quoted(path) for path in caches)
        lines.append("(allow file-read* file-write* %s)" % paths)
        lines.append('(allow file-issue-extension (require-all (extension-class '
                     '"com.apple.app-sandbox.read-write") (require-any %s)))' % paths)
    return lines


def split_part_targets(folder, stem, count):
    """Real paths of the parts of a split model in folder that are links to files elsewhere."""
    targets = []
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return targets
    for name in names:
        match = SPLIT_PART.match(name)
        if not match or match.group("stem") != stem or match.group("count") != count:
            continue
        path = os.path.join(folder, name)
        target = os.path.realpath(path)
        if target != path and os.path.isfile(target) and target not in targets:
            targets.append(target)
    return targets


def model_rules(model):
    """Read rules for the model file: both of its paths, and a split model's other parts."""
    paths = []
    for path in (model, os.path.realpath(model)):
        if path not in paths:
            paths.append(path)
    lines = ["; the model"]
    for path in paths:
        lines.append("(allow file-read* (literal %s))" % quoted(path))
        folder, name = os.path.split(path)
        match = SPLIT_PART.match(name)
        if match:
            pattern = "^%s/%s-[0-9]+-of-%s\\.gguf$" % (
                regex_quoted(folder), regex_quoted(match.group("stem")), match.group("count"))
            # A regular expression literal (#"...") takes its backslashes as written, unlike a
            # string, and has no way to hold a quote (the profile is then refused whole), so a
            # quote in the path is matched as any one character.
            lines.append('(allow file-read* (regex #"%s"))' % pattern.replace('"', "."))
            # The kernel checks a file's real path, and in a Hugging Face snapshot every part is
            # a link of its own into the blobs folder, under a name the pattern does not match.
            for target in split_part_targets(folder, match.group("stem"), match.group("count")):
                if target not in paths:
                    paths.append(target)
    return lines


def llama_profile(engine_dir, model, port, cache_dir):
    lines = ["(version 1)", "(deny default)", "(debug deny)", '(import "bsd.sb")', "",
             "; the engine's own folder",
             "(allow file-read* process-exec (subpath %s))" % quoted(engine_dir), ""]
    lines += model_rules(model) + [""]
    lines += gpu_rules(engine_dir, cache_dir) + [""]
    lines += ["; its port of this Mac, and nothing else",
              "(deny network*)",
              '(allow network-bind (local ip "localhost:%d"))' % port,
              '(allow network-inbound (local ip "localhost:%d"))' % port]
    return "\n".join(lines) + "\n"


def write_profile(path, text):
    """Write the profile for this user only, replacing an older one in one step."""
    staging = "%s.%d" % (path, os.getpid())
    try:
        handle = os.fdopen(os.open(staging, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "w")
        with handle:
            handle.write(text)
        os.replace(staging, path)
    except OSError as exc:
        try:
            os.unlink(staging)
        except OSError:
            pass
        sys.stderr.write("inference_sandbox: cannot write %s: %s\n" % (path, exc))
        return False
    return True

AGENT_VM_DEFAULT_STORE = "~/Library/Application Support/agent-vm"


def model_grants(model_dir):
    """What an MLX model is read from: (folders, single files).

    The model folder itself, and for every link in it (or one folder below, where shards may be)
    the one file the link leads to. A Hugging Face snapshot is links into the repository's blobs
    folder; a user may also keep weights elsewhere and link them. Each link grants its own
    target and nothing beside it: the folder is the model's content, and a link to a file in the
    home folder must not open the folder that file is in.

    A link to a folder is followed only inside a Hugging Face repository (the model folder is in
    "snapshots", and the target is under the folder above that). Anywhere else it is left out:
    such a model loads without the sandbox, not with a wider one.
    """
    real_model = os.path.realpath(model_dir)
    repository = ""
    if os.path.basename(os.path.dirname(real_model)) == "snapshots":
        repository = os.path.dirname(os.path.dirname(real_model))
    folders = [model_dir]
    files = []
    pending = [(model_dir, 0)]
    while pending:
        folder, depth = pending.pop(0)
        try:
            names = sorted(os.listdir(folder))
        except OSError:
            continue
        for name in names:
            path = os.path.join(folder, name)
            if not os.path.islink(path):
                if depth == 0 and os.path.isdir(path):
                    pending.append((path, 1))
                continue
            real = os.path.realpath(path)
            if (real + "/").startswith(real_model + "/"):
                continue
            if os.path.isfile(real):
                if real not in files:
                    files.append(real)
            elif os.path.isdir(real) and repository and (real + "/").startswith(repository + "/"):
                if real not in folders:
                    folders.append(real)
    return folders, files


def local_port(base_url):
    """The port of a server on this Mac named by an http URL, or 0."""
    try:
        parts = urllib.parse.urlsplit(base_url)
        port = parts.port
    except ValueError:
        return 0
    if parts.hostname not in ("127.0.0.1", "localhost", "::1") or not port:
        return 0
    return port


def agent_profile(engine, target, config_path, servers, tools_box, agent_vm, agent_vm_home):
    """mlx-agent's sandbox profile for one launch, as its --sandbox-profile JSON object.

    Returns (profile, reason): profile is None when the agent must run unconfined, and reason
    says why in a few words (for the log).

    - engine "mlx": the GPU, the model's folder and the files its links lead to. "openai": a connection to the llama-server
      port of this Mac. "foundation": Apple's on-device model service.
    - no tool servers: nothing more.
    - tool servers in an AgentVM box: every server is `agent-vm exec`, which needs agent-vm
      itself, the box's record, its control socket and its exec log (the audit record: without
      the rule exec works and its lines are silently lost).
    - tool servers on this Mac: unconfined. Each server confines itself at startup, and a
      process under a profile cannot apply a second one.
    """
    # Always: Apple's on-device model. A conversation restored with a summary may have chosen it
    # as the summarizer whatever the engine is (session/prime's condense.backend).
    profile = {"foundation_models": True}
    if engine == "openai":
        port = local_port(target)
        if not port:
            return None, "the model server's address is not a port of this Mac"
        profile["network_connect"] = ["localhost:%d" % port]
    elif engine == "foundation":
        pass
    elif engine == "mlx":
        if not os.path.isabs(target) or not os.path.isdir(target):
            return None, "the model folder does not exist"
        profile["gpu"] = True
        profile["read_only"], linked = model_grants(target)
        if linked:
            profile["read_only_files"] = linked
    else:
        return None, "no profile for engine %s" % engine

    if not servers:
        return profile, ""
    if not tools_box:
        return None, "the tools run on this Mac"
    if not agent_vm or not os.path.isabs(agent_vm):
        return None, "the tools run in a box but agent-vm's path is unknown"
    for server in servers:
        args = server.get("args") if isinstance(server, dict) else None
        if (not isinstance(server, dict) or server.get("command") != agent_vm
                or not isinstance(args, list) or args[:3] != ["exec", "--box", tools_box]):
            return None, "a tool server is not an agent-vm exec into box %s" % tools_box
    store = os.path.expanduser(agent_vm_home or AGENT_VM_DEFAULT_STORE)
    box_dir = os.path.join(store, "Boxes", tools_box)
    profile["read_only_files"] = profile.get("read_only_files", []) + [
        config_path, box_dir, os.path.join(box_dir, "box.json")]
    profile["exec_files"] = [agent_vm]
    profile["unix_socket_connect"] = [os.path.join(box_dir, "control.sock")]
    profile["read_write_files"] = [os.path.join(box_dir, "exec.jsonl")]
    return profile, ""


def write_agent_profile(path, profile):
    """Write mlx-agent's profile JSON for this user only. True when written."""
    return write_profile(path, json.dumps(profile, indent=1, sort_keys=True) + "\n")


def run_llama(options):
    engine_dir = os.path.realpath(options.engine_dir)
    if not os.path.isdir(engine_dir):
        sys.stderr.write("inference_sandbox: the engine folder %s does not exist\n" % options.engine_dir)
        return 1
    if not os.path.isabs(options.model) or not os.path.isfile(options.model):
        sys.stderr.write("inference_sandbox: the model must be an existing file with an absolute path\n")
        return 1
    if not 1 <= options.port <= 65535:
        sys.stderr.write("inference_sandbox: the port must be between 1 and 65535\n")
        return 1
    text = llama_profile(engine_dir, options.model, options.port, user_cache_dir())
    return 0 if write_profile(options.out, text) else 1


def main():
    parser = argparse.ArgumentParser(prog="inference_sandbox.py", allow_abbrev=False)
    commands = parser.add_subparsers(dest="command", required=True)
    llama = commands.add_parser("llama", allow_abbrev=False)
    llama.add_argument("--engine-dir", required=True)
    llama.add_argument("--model", required=True)
    llama.add_argument("--port", required=True, type=int)
    llama.add_argument("--out", required=True)
    llama.set_defaults(run=run_llama)
    options = parser.parse_args()
    return options.run(options)


if __name__ == "__main__":
    sys.exit(main())
