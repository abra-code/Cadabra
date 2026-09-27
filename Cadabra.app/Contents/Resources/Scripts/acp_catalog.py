#!/usr/bin/env python3
"""Read the bundled ACP agent catalog and hand it to the shell library as TSV.

The catalog itself is Resources/acp-agents.json. It used to be a heredoc of tab-separated
lines inside aichat.acp.agents.library.sh, which made it awkward to extend and easy to break:
tab is IFS *whitespace*, so one empty field collapses into its neighbor and shifts every later
field left - and in this particular table that means prose sliding into the argv column, where
it would be RUN. JSON makes an absent value unambiguous and lets a row carry structure, most
usefully an "args" LIST, so "this agent takes no arguments" is [] instead of a single space
smuggled through a tab-separated field.

The shell side still reads TSV, because it can do that with `IFS=<tab> read` and no
interpreter of its own, and because the scan/consumer code already speaks it.

THE INVARIANT THIS FILE OWNS, and the reason the hand-maintained version kept going wrong:
every emitted field is non-empty and contains no tab, no carriage return and no newline.
Absent values become "-", which the shell reads as "none". Enforcing it in code rather than
in a comment is the actual improvement here - a human editing JSON cannot reintroduce the
collapsing-field bug, because this file will not emit an empty one.

Usage:
    acp_catalog.py rows   [<catalog.json>]
    acp_catalog.py custom [<catalog.json>]
    acp_catalog.py box <id> [<catalog.json>]
    acp_catalog.py box-list <id> allow|secrets [<catalog.json>]
    acp_catalog.py box-keys <id> [<catalog.json>]
    acp_catalog.py box-login <id> [<catalog.json>]
    acp_catalog.py box-unavailable <id> <level> [<catalog.json>]

"rows" emits, tab separated, one row per agent:
    id, label, command, args, url, summary, note

"custom" emits ONE tab-separated row from the catalog's "custom" object:
    label, url, summary, note

That object is not an agent - it is the prose the dialog shows while editing an agent the user
saved themselves, and the default name a new one gets. It sits outside the agents list so it
can never be selected as one, and it is read through a separate subcommand so a caller cannot
pick it up by accident while iterating the catalog.

"box" emits the agent's "box" object as ONE line of JSON: how it runs in an agent-vm box (its
argv in the guest, network rules, secrets, login hint, env and autonomy levels; the catalog's
comment names the keys). An agent with no box object, or an unknown id, emits nothing and exits 0:
"no box recipe" is an answer, and the caller falls back to the agent's own command. The object is
nested, which TSV cannot carry, so it travels as JSON and is read in Python, never in the shell.

"box-list" emits one value per line from the agent's box object, for the shell: "allow" gives
the network rules ("pack:anthropic", a host), "secrets" the variable name of each secret the
agent can use, in the catalog's order of preference. Values that are empty, or hold whitespace
(no rule or variable name does), are left out. Nothing for an agent with no box object.

"box-keys" emits, tab separated, one row per secret the agent can use, in the catalog's order:
    variable name, label, hint
for the Keys window: the label is a short name for a table cell, the hint how to get the key. A
secret whose variable name box-list would leave out is left out here too, and a missing label or
hint is "-".

"box-login" emits, on one line, the catalog's hint for logging in inside a kept box (the "login"
text), or nothing.

"box-unavailable" emits, on one line, the reason the agent cannot work at that autonomy level
(free, ask or plan) in a box, or nothing when it can. The reason is the level's "unavailable" text
(such as Codex's plan level), or, for "ask" and "plan", that the catalog does not say how to tell
this agent (no box object, or no such level): the level would not be applied, and the agent would
work more freely than chosen. "free" needs nothing applied, so it is always available. The dialog
refuses the choice with the reason.

A missing or unreadable catalog is reported on stderr and exits non-zero with NO rows on
stdout, so the dialog shows an empty list rather than a plausible-looking partial one.
"""
import json
import os
import sys

# The emitted columns, in order. This tuple is also the PRIVACY BOUNDARY of the catalog: a key
# in acp-agents.json that is not named here never reaches the shell, and therefore never reaches
# the dialog. "verification" is deliberately absent - it records what we probed and how, which is
# our provenance and not something a user running Cadabra on their own machine could check or act
# on. Adding a field here makes it user-visible, so do it on purpose.
FIELDS = ("id", "label", "command", "args", "url", "summary", "note")

# The custom object's columns. Same privacy rule, same never-empty rule.
CUSTOM_FIELDS = ("label", "url", "summary", "note")
ABSENT = "-"


def default_catalog_path():
    # Scripts/ lives beside the catalog's directory: <Resources>/Scripts/acp_catalog.py
    # -> <Resources>/acp-agents.json
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "acp-agents.json")


def flatten(value):
    """One line, no tabs, no empties. See the invariant note at the top of the file."""
    if value is None:
        return ABSENT
    if isinstance(value, (list, tuple)):
        value = " ".join(str(v) for v in value)
    # split()/join collapses tabs, newlines and runs of spaces in one step, which is exactly
    # the set of characters that would corrupt the row or the display.
    text = " ".join(str(value).split())
    return text if text else ABSENT


def load(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def agents_of(data):
    agents = data.get("agents")
    if not isinstance(agents, list):
        raise ValueError("catalog has no \"agents\" list")
    return agents


def emit_custom(data):
    """The custom-agent prose, or nothing at all if the catalog has none."""
    # A catalog whose root is a list or a string has no .get, and an AttributeError here would
    # print a traceback where "rows" prints one clear line for the same input.
    if not isinstance(data, dict):
        sys.stderr.write("acp_catalog: catalog root is not an object\n")
        return 1
    custom = data.get("custom")
    if not isinstance(custom, dict):
        sys.stderr.write("acp_catalog: catalog has no \"custom\" object\n")
        return 1
    sys.stdout.write("\t".join(flatten(custom.get(name)) for name in CUSTOM_FIELDS) + "\n")
    return 0


def box_of(data, agent_id):
    """The box object of the agent with this id, or None."""
    for agent in agents_of(data):
        if isinstance(agent, dict) and agent.get("id") == agent_id:
            box = agent.get("box")
            return box if isinstance(box, dict) else None
    return None


# The levels that restrict an agent, as the refusal names them. "free" is not here: it asks
# nothing of the agent, so it needs no recipe.
LEVEL_WORDS = {"ask": "ask before changes", "plan": "only plan"}


def box_list(box, which):
    """The box object's allow rules or secret variable names, as clean strings."""
    if which == "allow":
        values = box.get("allow")
    else:
        values = [entry.get("env") for entry in box.get("secrets") or [] if isinstance(entry, dict)]
    if not isinstance(values, list):
        return []
    return [value for value in values
            if isinstance(value, str) and value and not any(c.isspace() for c in value)]


def box_keys(box):
    """(variable name, label, hint) for each secret the agent can use, as box_list names them."""
    names = set(box_list(box, "secrets"))
    rows = []
    for entry in box.get("secrets") or []:
        if isinstance(entry, dict) and entry.get("env") in names:
            rows.append((entry["env"], flatten(entry.get("label")), flatten(entry.get("hint"))))
    return rows


def main():
    argv = sys.argv[1:]
    known = (argv and (argv[0] in ("rows", "custom")
                       or (argv[0] == "box" and len(argv) >= 2)
                       or (argv[0] in ("box-keys", "box-login") and len(argv) >= 2)
                       or (argv[0] == "box-list" and len(argv) >= 3 and argv[2] in ("allow", "secrets"))
                       or (argv[0] == "box-unavailable" and len(argv) >= 3)))
    if not known:
        sys.stderr.write("usage: acp_catalog.py rows|custom [<catalog.json>] | box <id> [<catalog.json>]"
                         " | box-list <id> allow|secrets [<catalog.json>]"
                         " | box-keys|box-login <id> [<catalog.json>]"
                         " | box-unavailable <id> <level> [<catalog.json>]\n")
        return 2
    rest = argv[2:] if argv[0] in ("box", "box-keys", "box-login") else argv[3:] if argv[0] in ("box-list", "box-unavailable") else argv[1:]
    path = rest[0] if rest else default_catalog_path()
    try:
        data = load(path)
    except Exception as exc:            # unreadable, absent, malformed - all the same to us
        sys.stderr.write("acp_catalog: cannot read %s: %s\n" % (path, exc))
        return 1

    if argv[0] == "custom":
        return emit_custom(data)

    if argv[0] == "box-unavailable":
        try:
            box = box_of(data, argv[1])
        except Exception as exc:
            sys.stderr.write("acp_catalog: cannot read %s: %s\n" % (path, exc))
            return 1
        levels = box.get("levels") if isinstance(box, dict) else None
        level = levels.get(argv[2]) if isinstance(levels, dict) else None
        reason = level.get("unavailable") if isinstance(level, dict) else None
        if reason is None and not isinstance(level, dict) and argv[2] in LEVEL_WORDS:
            reason = ("Cadabra does not know how to make this agent %s. In an AgentVM box it can work "
                      "without asking." % LEVEL_WORDS[argv[2]])
        if isinstance(reason, str) and reason.strip():
            sys.stdout.write(" ".join(reason.split()) + "\n")
        return 0

    if argv[0] == "box-list":
        try:
            box = box_of(data, argv[1])
            values = box_list(box, argv[2]) if box is not None else []
        except Exception as exc:
            sys.stderr.write("acp_catalog: cannot read %s: %s\n" % (path, exc))
            return 1
        for value in values:
            sys.stdout.write(value + "\n")
        return 0

    if argv[0] in ("box-keys", "box-login"):
        try:
            box = box_of(data, argv[1])
        except Exception as exc:
            sys.stderr.write("acp_catalog: cannot read %s: %s\n" % (path, exc))
            return 1
        if box is None:
            return 0
        if argv[0] == "box-keys":
            for row in box_keys(box):
                sys.stdout.write("\t".join(row) + "\n")
        else:
            login = flatten(box.get("login"))
            if login != ABSENT:
                sys.stdout.write(login + "\n")
        return 0

    if argv[0] == "box":
        try:
            box = box_of(data, argv[1])
        except Exception as exc:
            sys.stderr.write("acp_catalog: cannot read %s: %s\n" % (path, exc))
            return 1
        if box is not None:
            json.dump(box, sys.stdout, separators=(",", ":"))
            sys.stdout.write("\n")
        return 0

    try:
        agents = agents_of(data)
    except Exception as exc:
        sys.stderr.write("acp_catalog: cannot read %s: %s\n" % (path, exc))
        return 1

    out = []
    for agent in agents:
        if not isinstance(agent, dict):
            continue
        # An id is the one field with no sensible default: it keys the stored selection, so an
        # entry without one could never be selected, stored, or looked up again.
        agent_id = flatten(agent.get("id"))
        if agent_id == ABSENT:
            # ABSENT is what an absent value flattens to AND a legal one-character string, so
            # distinguish the two rather than reporting "no id" for an entry that has one and
            # merely collided with the sentinel. Vanishingly unlikely, but a diagnostic that
            # misdescribes its input costs more time than it ever saves.
            if " ".join(str(agent.get("id") or "").split()) == ABSENT:
                sys.stderr.write('acp_catalog: skipping an entry whose id is "%s", which this'
                                 ' format reserves to mean "absent"\n' % ABSENT)
            else:
                sys.stderr.write("acp_catalog: skipping an entry with no id\n")
            continue
        out.append("\t".join(flatten(agent.get(name)) for name in FIELDS))
    sys.stdout.write("".join(line + "\n" for line in out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
