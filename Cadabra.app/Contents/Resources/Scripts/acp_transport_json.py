#!/usr/bin/env python3
"""Emit the Chat element's ACP transport JSON for one chat window.

Called by aichat_acp_transport_json in aichat.mcp.servers.library.sh. Building the
argv and the JSON here (via json.dumps) keeps paths with spaces or quotes safe.
Agent mode is selected only when the generated MCP config lists >= 1 server;
otherwise the transport is plain chat (no --mcp-config).

Usage:
    acp_transport_json.py <agent_bin> <engine> <target> <mcp_config_path> <cwd> [tools]
                          [--box NAME --agent-vm PATH [--agent-vm-home DIR] --project DIR
                           [--read-only] --level free|ask|plan [--agent-id ID]
                           [--secret NAME ...] [--env NAME=VALUE ...]]
                          [--sandbox-out FILE [--tools-box NAME --agent-vm PATH
                           [--agent-vm-home DIR]]]

    The named options come after the positional ones. The first set applies to engine
    "external" only: the agent runs in an agent-vm box (see "IN A BOX" below). The second set
    applies to the other engines: mlx-agent confines itself (see "THE AGENT'S SANDBOX" below).

    [tools] is optional and defaults to "true": "readonly" hands the external agent only
    the servers that have no gated tools (see acp_mcp_servers); anything else hands over
    whatever the config lists.

    engine == "openai":     <target> is the llama-server base-url; mlx-agent talks to it.
    engine == "mlx":        <target> is a safetensors model directory loaded in-process.
    engine == "foundation": Apple's on-device model. <target> is UNUSED and expected to be
                            empty - the model belongs to the OS, and passing --model would be
                            refused by the agent because there is nothing to choose between.
    engine == "external":   an ACP agent that is NOT mlx-agent (opencode, the Claude Code
                            ACP adapter, anything the user configured). <agent_bin> is ignored and
                            <target> is the complete command line as the user typed it, split
                            here with shlex - so quoted paths with spaces survive, and the
                            string that is stored is the string that was shown.

HOW THE EXTERNAL PATH DIFFERS, and why it cannot share the mlx-agent one: MCP servers reach
mlx-agent through `--mcp-config <path>`, which is mlx-agent's own flag and means nothing to
any other agent. Every ACP agent instead takes its servers as the `mcpServers` array of
`session/new`, which the Chat element sends from the transport's `mcpServers` key
(ACPChatTransport.swift:225). So the same server list is delivered two different ways
depending on who is being launched, and the external path converts it.

The conversion drops `gatedTools`. That key is an mlx-agent extension - it is how the
bundled agent knows which tools to route back through Cadabra's approval card - and an
external agent neither understands it nor needs it: it runs its own permission model and
raises ACP `session/request_permission`, which the Chat element already renders. Passing it
on would be a foreign key in a spec-defined object for no gain.

IN A BOX (--box): the agent is wrapped in `agent-vm exec`, which runs it in the box with the
project shared at the same path:
    agent-vm exec --box B --project P [--read-only] [--secret S ...] [--env N=V ...] -- <argv>
- <argv> is the catalog's box.argv for --agent-id when the catalog has one (the agent's normal
  command may name a path on this Mac that does not exist in the box), else the user's command.
  So the caller passes --agent-id only for a catalog row whose command the user has not edited:
  an edited command is the user's and must run as typed.
- The environment goes through `--env`, so it reaches the program in the guest: the catalog's
  box.env, then the level's env, then the caller's --env, a later value replacing an earlier one.
  No env.PATH: the guest has its own PATH, and the Mac's would mean nothing there.
- Secrets are agent-vm Keychain secrets, named with --secret; their values never pass through
  here (agent-vm puts them into the program's environment in the guest).
- The level (--level, required with --box) is how much the agent asks before acting, applied the way
  the catalog's box.levels says: an ACP session mode goes out as "sessionConfig": {"mode": ...}
  for ChatView to set after session/new; extra env joins the environment; a level the agent
  cannot do ("unavailable") is refused with nothing on stdout, like an empty command, and so is
  "ask" or "plan" for an agent whose recipe does not say how to apply it (none, for a command
  the user typed): it would run with no restriction.
- --agent-vm-home is agent-vm's store root when Cadabra uses another one (its developer
  setting): it goes into the transport's env as AGENT_VM_HOME, for agent-vm itself on this Mac,
  so the exec finds the box Cadabra started in that store.
- cwd is the project, which is also its path in the box. startupTimeoutSeconds is 60: the box is
  started before this transport is used, so the time covers only the agent's own start.
- mcpServers, with tools on: the config at <mcp_config_path> lists Cadabra's servers as copied
  into the box (generate_mcp_configs.py --client in-box), so the agent starts them in the box
  itself; "readonly" passes only servers with no gated tools, as on this Mac.

THE AGENT'S SANDBOX (--sandbox-out): mlx-agent holds the model and the conversation, and a
model's output decides which tools are called. With --sandbox-out it is started with
`--sandbox-profile FILE`, a profile written here for this launch (inference_sandbox.agent_profile):
the model's folders and the GPU (mlx), the llama-server port of this Mac (openai), Apple's
on-device model service (always: a restored conversation may summarize with it).
- No tool servers: nothing more.
- Tool servers in an AgentVM box (--tools-box, with agent-vm's path and store): agent-vm and that
  box's record, control socket and exec log.
- Tool servers on this Mac: NO profile, and the agent runs as before. Each server confines
  itself at startup, and a process under a profile cannot apply a second one.
- A profile that cannot be written refuses the transport (nothing on stdout): the agent is not
  started unconfined when confinement was asked for.

Writes one line of JSON to stdout and nothing else, so the caller's stdout stays
pure JSON.
"""
import argparse
import json
import os
import shlex
import sys

import acp_agent_env
import acp_catalog
import inference_sandbox

# Boxed agents get this long to answer initialize and session/new (a cold Node start in the guest).
BOX_STARTUP_TIMEOUT_SECONDS = 60
LEVELS = ("free", "ask", "plan")


def read_servers(cfg):
    """The generated MCP config's server list, or [] for anything unreadable.

    A missing, empty or broken config must never wedge the window - it degrades to a chat
    with no tools, which is a working chat.
    """
    try:
        if os.path.isfile(cfg):
            with open(cfg) as handle:
                servers = json.load(handle).get("servers", [])
                return servers if isinstance(servers, list) else []
    except Exception:
        pass
    return []


def _declares_no_gated_tools(server):
    """True only when this entry POSITIVELY says none of its tools need a permission prompt.

    The question is asked this way round on purpose. The tempting test is "does it have a
    truthy gatedTools", or "is gatedTools a non-empty list", and both hand the server over for
    every shape they fail to recognize - null, 0, "", {}, false, and for the isinstance version
    also a string or a number. Every one of those means WE CANNOT TELL, and "cannot tell" must
    not resolve to "give a third-party agent this server".

    So only two shapes qualify, and they are the only two the generator ever writes: the key
    absent (it is set only when the gated list is non-empty), or an explicitly empty list.
    Anything else is either real gating or a config we do not understand, and both are withheld.

    Note `"gatedTools" in server` rather than a .get() - an explicit null would otherwise be
    indistinguishable from absent, and null is a shape we do not understand.
    """
    if "gatedTools" not in server:
        return True
    gated = server["gatedTools"]
    return isinstance(gated, list) and not gated


def acp_mcp_servers(servers, readonly_only=False):
    """Cadabra's server list in the shape ACP's session/new expects.

    Only the spec's stdio fields survive: name, command, args, env. `gatedTools` is
    mlx-agent's own extension and is dropped (see the module docstring).

    readonly_only is the "Read-only Servers" setting. `gatedTools` lists the tools that
    mlx-agent must route through Cadabra's approval card, computed fail-closed by probing
    each server: a tool is gated unless it positively declares MCP's readOnlyHint. So a
    server with NO gatedTools is one whose every tool declared itself read-only, and
    dropping the rest is the closest thing to Cadabra-side gating that an external agent
    can be held to - it cannot be asked to honor a key it does not implement, but it can
    only call tools it was handed.

    The filter is SERVER granular, not tool granular, because session/new's mcpServers has
    no per-tool selector. A server with one mutating tool goes entirely, which is why the
    setting is named for servers rather than for tools.

    That "absent means read-only" reading is only safe because generate_mcp_configs.py
    OMITS a server it could not probe, rather than writing it out with no gatedTools - the
    two would otherwise be indistinguishable here, and this filter would be fail-open.

    `env` IS ALWAYS EMITTED, even empty. It is a mapping in our config and an array of
    {name, value} in ACP, so it has to be converted either way - but it is also REQUIRED, and
    omitting it when a server happens to have no environment is fatal. Measured against
    opencode 1.17.13: an entry of {name, command, args} is rejected with -32602 Invalid
    params, and so is one whose `env` is passed through as a mapping; only the array form is
    accepted. One malformed entry rejects the WHOLE session/new call, so a single env-less
    server takes every tool in the session down with it - and the error names no server, it
    is a schema-union dump that reads like an unrelated problem. Cadabra's own `pdf` server
    has no env today (generate_mcp_configs.py only sets it when non-empty), so this is a live
    case, not a hypothetical one.
    """
    out = []
    for server in servers:
        if not isinstance(server, dict) or not server.get("command"):
            continue
        if readonly_only and not _declares_no_gated_tools(server):
            continue
        env = server.get("env")
        entry = {"name": str(server.get("name", "")),
                 "command": str(server["command"]),
                 "args": [str(a) for a in server.get("args", []) or []],
                 "env": [{"name": str(k), "value": str(v)} for k, v in env.items()]
                        if isinstance(env, dict) else []}
        out.append(entry)
    return out


def parse_box_options(words):
    """The named options after the positional ones, or None when there are none."""
    if not words:
        return None
    # No abbreviations: "--read" must not quietly mean --read-only. And no default level: the UI
    # decides it (free by default in a box), and a caller that forgot it must not get the freest.
    parser = argparse.ArgumentParser(prog="acp_transport_json.py", add_help=False, allow_abbrev=False)
    parser.add_argument("--box", required=True)
    parser.add_argument("--agent-vm", required=True)
    parser.add_argument("--agent-vm-home", default="")
    parser.add_argument("--project", required=True)
    parser.add_argument("--read-only", action="store_true")
    parser.add_argument("--agent-id", default="")
    parser.add_argument("--level", required=True, choices=LEVELS)
    parser.add_argument("--secret", action="append", default=[])
    parser.add_argument("--env", action="append", default=[])
    return parser.parse_args(words)


def parse_sandbox_options(words):
    """The named options of a bundled engine (the agent's sandbox), or None when there are none."""
    if not words:
        return None
    parser = argparse.ArgumentParser(prog="acp_transport_json.py", add_help=False, allow_abbrev=False)
    parser.add_argument("--sandbox-out", required=True)
    parser.add_argument("--tools-box", default="")
    parser.add_argument("--agent-vm", default="")
    parser.add_argument("--agent-vm-home", default="")
    return parser.parse_args(words)


def sandbox_arguments(sandbox, engine, target, cfg, servers):
    """mlx-agent's extra arguments for its sandbox: [] to run unconfined, None to refuse."""
    if sandbox is None:
        return []
    profile, reason = inference_sandbox.agent_profile(
        engine, target, cfg, servers, sandbox.tools_box, sandbox.agent_vm, sandbox.agent_vm_home)
    if profile is None:
        # Said on stderr, which is the handler's log: the user chose where the tools run, and
        # that choice, not an error, is why the agent is unconfined.
        sys.stderr.write("acp_transport_json: the agent runs without a sandbox: %s\n" % reason)
        return []
    if not os.path.isabs(sandbox.sandbox_out):
        sys.stderr.write("acp_transport_json: --sandbox-out must be an absolute path\n")
        return None
    if not inference_sandbox.write_agent_profile(sandbox.sandbox_out, profile):
        return None
    return ["--sandbox-profile", sandbox.sandbox_out]


def catalog_box(agent_id):
    """The catalog's box object for this agent id, or None (no id, no object, or no catalog)."""
    if not agent_id:
        return None
    try:
        return acp_catalog.box_of(acp_catalog.load(acp_catalog.default_catalog_path()), agent_id)
    except Exception as exc:
        # Visible, since the fallback is the user's command, which may be a path on this Mac.
        sys.stderr.write("acp_transport_json: cannot read the agent catalog (%s); using the agent's own command\n" % exc)
        return None


def box_transport(options, user_argv):
    """The transport for an agent in a box, or None after a message on stderr."""
    if not options.box:
        sys.stderr.write("acp_transport_json: --box needs a box name\n")
        return None
    if not os.path.isabs(options.project):
        sys.stderr.write("acp_transport_json: the project must be an absolute path\n")
        return None
    if not os.path.isabs(options.agent_vm):
        sys.stderr.write("acp_transport_json: the agent-vm path must be absolute\n")
        return None
    if options.agent_vm_home and not os.path.isabs(options.agent_vm_home):
        sys.stderr.write("acp_transport_json: the agent-vm store (--agent-vm-home) must be an absolute path\n")
        return None
    recipe = catalog_box(options.agent_id) or {}
    argv = recipe.get("argv") if isinstance(recipe.get("argv"), list) else None
    argv = [str(a) for a in argv if str(a) != ""] if argv else user_argv
    if not argv:
        sys.stderr.write("acp_transport_json: external agent has an empty command\n")
        return None

    environment = {}
    base_env = recipe.get("env")
    if isinstance(base_env, dict):
        environment.update({str(k): str(v) for k, v in base_env.items()})
    session_config = {}
    levels = recipe.get("levels") if isinstance(recipe.get("levels"), dict) else {}
    level = levels.get(options.level)
    if options.level != "free" and not isinstance(level, dict):
        # Nothing says how to tell this agent to ask or to plan, so it would start with no
        # restriction at all - more freely than the user chose. Refused like an unavailable level.
        sys.stderr.write("acp_transport_json: Cadabra does not know how to make this agent %s\n"
                         % ("ask before changes" if options.level == "ask" else "only plan"))
        return None
    if isinstance(level, dict):
        if level.get("unavailable"):
            sys.stderr.write("acp_transport_json: %s\n" % level["unavailable"])
            return None
        if isinstance(level.get("env"), dict):
            environment.update({str(k): str(v) for k, v in level["env"].items()})
        if level.get("mode"):
            session_config["mode"] = str(level["mode"])
    for entry in options.env:
        name, separator, value = entry.partition("=")
        if not separator or not name:
            sys.stderr.write("acp_transport_json: --env needs NAME=VALUE, not %r\n" % entry)
            return None
        environment[name] = value

    command = [options.agent_vm, "exec", "--box", options.box, "--project", options.project]
    if options.read_only:
        command.append("--read-only")
    for name in options.secret:
        command += ["--secret", name]
    for name in sorted(environment):
        command += ["--env", "%s=%s" % (name, environment[name])]
    command += ["--"] + argv
    transport = {"command": command, "cwd": options.project,
                 "startupTimeoutSeconds": BOX_STARTUP_TIMEOUT_SECONDS}
    if options.agent_vm_home:
        transport["env"] = {"AGENT_VM_HOME": options.agent_vm_home}
    if session_config:
        transport["sessionConfig"] = session_config
    return transport


def main():
    positional = sys.argv[1:]
    named = []
    for index, word in enumerate(positional):
        if index >= 5 and word.startswith("--"):
            positional, named = positional[:index], positional[index:]
            break
    agent, engine, target, cfg, cwd = positional[0:5]
    options = None
    sandbox = None
    try:
        if engine == "external":
            options = parse_box_options(named)
        else:
            sandbox = parse_sandbox_options(named)
    except SystemExit:
        # argparse has written its message to stderr; nothing on stdout, so the caller alerts.
        return
    # The session's tools setting, as the dialog's picker tags spell it: "true" (all
    # servers), "readonly" (only servers with no gated tools), "false" (no config was
    # generated at all, so there is nothing here to filter). Optional and defaulting to
    # "true" so an older caller that passes five arguments behaves exactly as before.
    # Absent means "true" so a five-argument caller behaves exactly as before. Anything
    # PRESENT but not "true" filters, rather than only the exact string "readonly": ok.sh
    # already coerces an unrecognized setting to the most restrictive one, and a second layer
    # that quietly read an unknown value as "hand over everything" would be the two of them
    # disagreeing about the same input - which is how a permission gap opens without anyone
    # editing the line that has the bug. "false" lands here too and costs nothing: that path
    # deleted the config, so there are no servers to filter.
    tools = positional[5] if len(positional) > 5 else "true"
    # NO --digest-backend IS PASSED, and that is a decision rather than an omission. It is a launch
    # flag: the agent fixes its summarizer when it starts, so a value here would answer for every
    # conversation the window ever opens. Which model summarizes a condensed restore is a per
    # conversation choice, and it rides on session/prime's condense object (`backend`) with the
    # restore that asked for it. Absent, mlx-agent's own default applies to anything that arrives
    # without one, which is what an unanswered conversation should get.

    # An agent that is not ours: the command line arrives as one user-typed string and is split
    # HERE rather than by a shell, so a path with spaces survives if it is quoted and nothing is
    # ever glob-expanded or word-split behind the user's back.
    if engine == "external":
        try:
            argv = shlex.split(target)
        except ValueError:
            # Unbalanced quotes. Refusing beats guessing: a "helpful" fallback split would run
            # something the user did not type.
            sys.stderr.write("acp_transport_json: external command has unbalanced quotes\n")
            argv = []
        # A lone empty token (`""` splits to ['']) is not a runnable command either, and it
        # would otherwise sail past the check below and build command: [""].
        argv = [a for a in argv if a != ""]
        if not argv:
            # NOTHING ON STDOUT, so the caller's `[ -n "$chat_config" ]` test fails and it
            # alerts. This used to emit `{"protocol":"local","transport":{"reply":"echo"}}` as
            # a safe-looking degradation, which was the worst available outcome: `local` is
            # ChatView's built-in demo transport and it never fails to construct, so the window
            # opened looking healthy - real title, enabled composer - and echoed the user's own
            # messages back at them, with no error anywhere and nothing to suggest the agent
            # had not started. A refusal the caller can see beats a chat that silently is not
            # one.
            sys.stderr.write("acp_transport_json: external agent has an empty command\n")
            return
        if options is not None:
            transport = box_transport(options, argv)
            if transport is None:
                return
            # Cadabra's servers, copied into the box, as the agent starts them there (the config
            # the caller generated with --client in-box): their box paths, no agent-vm exec.
            if tools != "false":
                servers = acp_mcp_servers(read_servers(cfg), readonly_only=(tools != "true"))
                if servers:
                    transport["mcpServers"] = servers
            json.dump({"protocol": "acp", "transport": transport}, sys.stdout)
            sys.stdout.write("\n")
            return
        # env.PATH, because the app's own PATH is not enough to launch an agent that is an
        # interpreter script. ChatView merges this over the inherited environment and it is
        # what resolves the shebang's `node` (ACPChatTransport.swift:92). The probe behind the
        # Test button uses the identical value, so the two cannot disagree. See acp_agent_env.
        transport = {"command": argv, "cwd": cwd,
                     "env": {"PATH": acp_agent_env.launch_path()}}
        servers = acp_mcp_servers(read_servers(cfg), readonly_only=(tools != "true"))
        if servers:
            transport["mcpServers"] = servers
        json.dump({"protocol": "acp", "transport": transport}, sys.stdout)
        sys.stdout.write("\n")
        return

    # Dispatched explicitly rather than "openai or else --model": the on-device engine has no
    # target, so falling through to the else would build `--model ""` and start an agent that
    # fails on an empty model path instead of using the model the user picked.
    if engine == "openai":
        argv = [agent, "acp", "--backend", "openai", "--base-url", target]
    elif engine == "foundation":
        argv = [agent, "acp", "--backend", "foundation"]
    else:
        argv = [agent, "acp", "--model", target]

    # Agent mode only when the config parsed and lists at least one server. A missing,
    # empty, or broken config leaves servers empty, so the transport falls back to plain
    # chat rather than wedging the window.
    servers = read_servers(cfg)
    if servers:
        argv += ["--mcp-config", cfg]

    extra = sandbox_arguments(sandbox, engine, target, cfg, servers)
    if extra is None:
        return
    argv += extra

    json.dump({"protocol": "acp", "transport": {"command": argv, "cwd": cwd}}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
