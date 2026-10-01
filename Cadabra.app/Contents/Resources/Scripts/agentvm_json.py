#!/usr/bin/env python3
"""Turn agent-vm's --json output into tab-separated rows for the shell library.

aichat.agentvm.library.sh runs agent-vm and pipes its JSON here; nothing else in Cadabra reads
agent-vm's output. agent-vm's human text is for people and changes freely, while its --json
output is a contract, so the shell never parses the text and this file never guesses at it.

THE SAME INVARIANT AS acp_catalog.py: every emitted field is non-empty and contains no tab,
carriage return or newline. Tab is IFS whitespace, so an empty field would collapse into its
neighbor under `IFS=<tab> read` and shift every later field left. Absent values are "-";
control characters inside a value become "?" (a path that holds one is shown mangled rather
than splitting a row). Booleans are "true" or "false"; lists are comma-joined.

Usage (the JSON on stdin):
    agentvm_json.py version   <- agent-vm version --json
    agentvm_json.py status    <- agent-vm box status <box> --json
    agentvm_json.py doctor    <- agent-vm doctor --json
    agentvm_json.py images    <- agent-vm image list --json
    agentvm_json.py boxes     <- agent-vm box list --json
    agentvm_json.py packs     <- agent-vm box packs --json
    agentvm_json.py execlog   <- agent-vm box execlog <box> --json
    agentvm_json.py netlog    <- agent-vm box netlog <box> --json
    agentvm_json.py secrets   <- agent-vm secret list --json
    agentvm_json.py sizes     <- agent-vm image info <image> --json, or box info <box> --json
    agentvm_json.py sessions  <- agent-vm session list --json, or session start|end|discard --json
    agentvm_json.py report-summary <- agent-vm session report <id> --json
    agentvm_json.py changes   <- agent-vm session report <id> --json
    agentvm_json.py undo      <- agent-vm session undo <id> [--path P...] --json
    agentvm_json.py recipe <recipe.json>   an image recipe file, read directly
The job-log readers at the end (log_progress, log_error) are for agentvm_job.py, which imports
this file.

"version" emits one row:
    version, path, guestVersion, guestFeatures, guestDigest, guestError
"status" emits one row:
    state, pid, supervisorVersion, supervisorPath, startedAt, project, projectReadOnly,
    activeExecs, guestVersion, guestFeatures, image, statusError, ownerPid, memoryGB
  ownerPid is the process whose exit stops the box ("-" for none); memoryGB is the box's memory,
  from its record.
"doctor" emits one row per check:
    name, status, detail
"images" emits one row per image:
    name, state, failure, macOS, basedOn, ownSize, needs, recipe, created, guestVersion,
    cpus, memoryGB, diskGB, path, needKinds
  macOS is "27.0 (26A428)"; ownSize is "-" (agent-vm's lists measure nothing; "sizes"
  reads image info), and is kept so the later columns keep their places; needs is
  for people ("guest update, Full Disk Access"), needKinds for code ("guest-update,...").
"boxes" emits one row per box:
    name, state, image, network, cpus, memoryGB, ownSize, pid, project, projectReadOnly,
    activeExecs, disposable, ownerPid, startedAt, supervisorVersion, path, netMode, rules
  network is for people ("allowlist, 2 rules"); rules is the allow list, comma-joined; ownSize
  is "-", as for images.
"packs" emits one row per pack:
    name, hosts, problem
  problem is agent-vm's reason a user pack cannot be used; such a pack has no hosts. "-" for a
  usable pack.
"execlog" emits one row per program run, oldest first:
    started, status, seconds, program, prompts, stoppedOnPrompt
  status is "no end recorded" while the run goes on, and also when its client died without
  writing the end (agent-vm's own words: the log cannot tell the two apart; a stopped box's
  run is over either way); program is the argv, space-joined; prompts are the
  macOS privacy prompts the run waited on, joined with "; ".
"netlog" emits one row per entry, oldest first:
    time, decision, host, port, method, reason
"sizes" emits one row, the space an image or a box takes (agent-vm measures it only in
`image info` and `box info`; the lists leave it out to stay quick):
    ownSize, totalSize, addedOverBase, addedSize
  ownSize is what deleting it frees ("280 MB"), totalSize all it holds, shared or not; for an
  image built from another, addedOverBase names that image and addedSize what the disk added.
"secrets" emits one row per Keychain secret agent-vm keeps (names only; agent-vm never prints a
value):
    name, readable
  readable is "false" when macOS would ask before agent-vm could read it (a rebuilt agent-vm
  that is not yet on the item's access list, say).
"sessions" emits one row per session (one for start, end and discard, which answer with the
session itself), oldest first:
    id, state, project, startSeconds, snapshotPath
  state is active, ended, undone or discarded; startSeconds is when the snapshot was taken, in
  seconds since 1970; project is the folder as agent-vm resolved it (no symbolic links).
"report-summary" emits one row, what a session's project changed since its snapshot:
    changes, flaggedHigh, flaggedMedium, warnings, flagged
  changes counts what undo would restore (an entry inside an added or deleted folder is part of
  the folder's change, and is listed in the report only when flagged); flaggedHigh and
  flaggedMedium count those changes by their most severe flag, a folder's including the flags of
  the entries inside it (agent-vm's own summary counts the entries); warnings counts the report's warnings (a clock that moved, say). flagged is for people: the
  first REPORT_FLAGGED_SHOWN flagged changes, most severe first, each "path (reason)", joined
  with "; ", then "and N more" when there are more.
"changes" emits one row per change of a session report, flagged first:
    severity, change, path, why, type, size, previousSize, coveredBy, symlinkTarget, entriesInside
  severity is "high" or "medium" (a change's most severe flag; for a folder whose change covers
  flagged entries, theirs too); change is for people ("Added", "Deleted folder",
  "Permissions"); why is the flag's reason, or for such a folder "holds N flagged entries, listed below
  it"; coveredBy is that folder for an entry it covers, which is listed right after it and undone
  with it. Changes are ordered by severity, then path, each folder's flagged entries after it.
"undo" emits one row, what `session undo` did:
    restored, remaining, failed, failures, state
  restored and failed count entries; failures is for people ("path: reason; ..."); remaining
  counts changes still undoable; state is the session's afterwards.
"recipe" emits the recipe, then one row per input and per parameter, in the file's order:
    kind (recipe, input or parameter), name, required, default, description
  The recipe's own row carries commandLineTools in the default column (true, false, or "-" when
  the recipe leaves it to agent-vm). Inputs are always required; a parameter is required when it
  has no default. An empty default is shown as "-", like any empty field.
Input that is not JSON, or JSON of the wrong shape, is reported on stderr and exits 1 with
nothing on stdout, so a caller never reads a plausible-looking partial row.
"""
import json
import sys

ABSENT = "-"


def field(value):
    """One TSV field: never empty, never a tab or line break."""
    if value is None:
        return ABSENT
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(int(value)) if float(value).is_integer() else str(value)
    if isinstance(value, list):
        text = ",".join(str(item) for item in value)
    else:
        text = str(value)
    text = "".join("?" if ch in "\t\r\n" or ord(ch) < 32 else ch for ch in text)
    return text if text else ABSENT


def row(values):
    return "\t".join(field(v) for v in values)


def need_object(data, what):
    if not isinstance(data, dict):
        raise ValueError(f"expected a JSON object from {what}")
    return data


def need_list(data, what):
    if not isinstance(data, list):
        raise ValueError(f"expected a JSON list from {what}")
    return data


def objects(items):
    return [item for item in items if isinstance(item, dict)]


def sub(data, key):
    value = data.get(key)
    return value if isinstance(value, dict) else {}


def size_text(count):
    """Bytes for people, in decimal units as agent-vm's own text output shows them."""
    if not isinstance(count, (int, float)) or isinstance(count, bool) or count < 0:
        return None
    for unit, scale in (("TB", 10 ** 12), ("GB", 10 ** 9), ("MB", 10 ** 6), ("KB", 10 ** 3)):
        if count >= scale:
            amount = count / scale
            return f"{amount:.1f} {unit}" if amount < 10 else f"{amount:.0f} {unit}"
    return f"{int(count)} bytes"


def gigabytes(count):
    if not isinstance(count, (int, float)) or isinstance(count, bool):
        return None
    return round(count / (1 << 30))


def own_size(data):
    usage = sub(data, "diskUsage")
    unshared = usage.get("unsharedBytes")
    return size_text(unshared if unshared is not None else usage.get("bytes"))


def day(timestamp):
    return timestamp[:10] if isinstance(timestamp, str) and len(timestamp) >= 10 else None


def version_rows(data):
    data = need_object(data, "agent-vm version --json")
    daemon = sub(data, "guestDaemon")
    yield row([data.get("version"), data.get("path"),
               daemon.get("version"), daemon.get("features"), daemon.get("digest"),
               daemon.get("error")])


def status_rows(data):
    data = need_object(data, "agent-vm box status --json")
    record = sub(data, "box")
    yield row([data.get("state"), data.get("pid"),
               data.get("supervisorVersion"), data.get("supervisorPath"), data.get("startedAt"),
               data.get("project"), data.get("projectReadOnly"), data.get("activeExecs"),
               data.get("guestVersion"), data.get("guestFeatures"),
               record.get("image"), data.get("statusError"),
               data.get("ownerPid"), gigabytes(record.get("memoryBytes"))])


def doctor_rows(data):
    data = need_object(data, "agent-vm doctor --json")
    checks = data.get("checks")
    if not isinstance(checks, list):
        raise ValueError("agent-vm doctor --json has no checks list")
    for check in objects(checks):
        yield row([check.get("name"), check.get("status"), check.get("detail")])


NEED_WORDS = {"guest-update": "guest update", "full-disk-access": "Full Disk Access"}


def image_rows(data):
    for image in objects(need_list(data, "agent-vm image list --json")):
        version, build = image.get("macOSVersion"), image.get("macOSBuild")
        macos = f"{version} ({build})" if version and build else (version or build)
        needs = objects(image.get("needs") or [])
        kinds = [need.get("kind") for need in needs if need.get("kind")]
        words = [NEED_WORDS.get(kind, kind) for kind in kinds]
        yield row([image.get("name"), image.get("state"), image.get("failure"), macos,
                   sub(image, "derivedFrom").get("image"), own_size(image), ", ".join(words),
                   sub(image, "recipe").get("description"), day(image.get("createdAt")),
                   image.get("guestVersion"), image.get("cpuCount"),
                   gigabytes(image.get("memoryBytes")), gigabytes(image.get("diskBytes")),
                   image.get("path"), kinds])


def box_rows(data):
    for entry in objects(need_list(data, "agent-vm box list --json")):
        record = sub(entry, "box")
        network = sub(record, "network")
        mode = network.get("mode")
        rules = [rule for rule in (network.get("allow") or []) if isinstance(rule, str)]
        if mode == "allowlist":
            described = f"allowlist, {len(rules)} rule{'' if len(rules) == 1 else 's'}"
        else:
            described = mode
        yield row([record.get("name"), entry.get("state"), record.get("image"), described,
                   record.get("cpuCount"), gigabytes(record.get("memoryBytes")), own_size(entry),
                   entry.get("pid"), entry.get("project"), entry.get("projectReadOnly"),
                   entry.get("activeExecs"),
                   entry.get("disposable", record.get("disposable")), entry.get("ownerPid"),
                   entry.get("startedAt"), entry.get("supervisorVersion"), entry.get("path"),
                   mode, rules])


def pack_rows(data):
    for pack in objects(need_list(data, "agent-vm box packs --json")):
        yield row([pack.get("name"), pack.get("hosts"), pack.get("problem")])


def execlog_rows(data):
    for entry in objects(need_list(data, "agent-vm box execlog --json")):
        argv = entry.get("argv")
        program = " ".join(str(arg) for arg in argv) if isinstance(argv, list) else None
        prompts = [prompt for prompt in (entry.get("prompts") or []) if isinstance(prompt, str)]
        status = entry.get("status")
        yield row([entry.get("started"), "no end recorded" if status is None else status,
                   entry.get("seconds"), program, "; ".join(prompts),
                   entry.get("stoppedOnPrompt", False)])


def size_rows(data):
    data = need_object(data, "agent-vm image info / box info --json")
    added = sub(data, "addedOverBase")
    yield row([own_size(data), size_text(sub(data, "diskUsage").get("bytes")),
               added.get("image"), size_text(added.get("bytes"))])


def secret_rows(data):
    for entry in objects(need_list(data, "agent-vm secret list --json")):
        yield row([entry.get("name"), entry.get("readable")])


def netlog_rows(data):
    for entry in objects(need_list(data, "agent-vm box netlog --json")):
        yield row([entry.get("time"), entry.get("decision"), entry.get("host"), entry.get("port"),
                   entry.get("method"), entry.get("reason") or entry.get("rule")])


def session_row(session):
    return row([session.get("id"), session.get("state"), session.get("project"),
                session.get("startSeconds"), session.get("snapshotPath")])


def session_rows(data):
    if isinstance(data, list):
        for session in objects(data):
            yield session_row(session)
    else:
        yield session_row(need_object(data, "agent-vm session --json"))


SEVERITY_RANK = {"high": 0, "medium": 1}
REPORT_FLAGGED_SHOWN = 6


def change_flag(change):
    """The change's most severe high or medium flag, or None (info flags do not count)."""
    flags = [flag for flag in objects(change.get("flags") or []) if flag.get("severity") in SEVERITY_RANK]
    flags.sort(key=lambda flag: SEVERITY_RANK[flag["severity"]])
    return flags[0] if flags else None


def report_summary_rows(data):
    data = need_object(data, "agent-vm session report --json")
    changes = objects(need_list(data.get("changes"), "agent-vm session report --json changes"))
    # The changes undo restores; an entry covered by a folder's change is listed only for its flag,
    # and counts toward that folder.
    top = [change for change in changes if change.get("coveredByAncestor") is not True]
    rank = {}
    for change in top:
        flag = change_flag(change)
        rank[str(change.get("path"))] = SEVERITY_RANK[flag["severity"]] if flag else len(SEVERITY_RANK)
    for change in changes:
        flag = change_flag(change)
        if change.get("coveredByAncestor") is not True or flag is None:
            continue
        # Up the path to the folder whose change covers it: a few lookups, where a scan of every
        # change would be quadratic in a new node_modules full of flagged executables.
        folder = str(change.get("path"))
        while "/" in folder:
            folder = folder.rsplit("/", 1)[0]
            if folder in rank:
                rank[folder] = min(rank[folder], SEVERITY_RANK[flag["severity"]])
                break
    flagged = [(change, change_flag(change)) for change in changes]
    flagged = [(change, flag) for change, flag in flagged if flag is not None]
    flagged.sort(key=lambda pair: (SEVERITY_RANK[pair[1]["severity"]], str(pair[0].get("path"))))
    shown = ["%s (%s)" % (change.get("path"), flag.get("reason") or flag.get("rule"))
             for change, flag in flagged[:REPORT_FLAGGED_SHOWN]]
    if len(flagged) > REPORT_FLAGGED_SHOWN:
        shown.append("and %d more" % (len(flagged) - REPORT_FLAGGED_SHOWN))
    warnings = data.get("warnings")
    yield row([len(top), sum(1 for value in rank.values() if value == SEVERITY_RANK["high"]),
               sum(1 for value in rank.values() if value == SEVERITY_RANK["medium"]),
               len(warnings) if isinstance(warnings, list) else 0, "; ".join(shown)])


KIND_WORDS = {"added": "Added", "deleted": "Deleted", "modified": "Modified",
              "typeChanged": "Type changed", "metadata": "Permissions"}


def change_rows(data):
    data = need_object(data, "agent-vm session report --json")
    changes = objects(need_list(data.get("changes"), "agent-vm session report --json changes"))
    tops = {str(change.get("path")): change for change in changes
            if change.get("coveredByAncestor") is not True}

    def covering(change):
        if change.get("coveredByAncestor") is not True:
            return None
        folder = str(change.get("path"))
        while "/" in folder:
            folder = folder.rsplit("/", 1)[0]
            if folder in tops:
                return folder
        return None

    def rank(flag):
        return SEVERITY_RANK[flag["severity"]] if flag else len(SEVERITY_RANK)

    # A change undo restores, ranked by its own flag and those of the flagged entries inside it,
    # which follow it in the list.
    group_rank = {path: rank(change_flag(change)) for path, change in tops.items()}
    inside = {}
    for change in changes:
        folder = covering(change)
        if folder is not None:
            group_rank[folder] = min(group_rank[folder], rank(change_flag(change)))
            inside[folder] = inside.get(folder, 0) + 1

    def order(change):
        folder = covering(change)
        group = folder if folder is not None else str(change.get("path"))
        return (group_rank.get(group, len(SEVERITY_RANK)), group, folder is not None, str(change.get("path")))

    for change in sorted(changes, key=order):
        flag = change_flag(change)
        path = str(change.get("path"))
        kind = change.get("kind")
        word = KIND_WORDS.get(kind, kind)
        if change.get("type") == "directory" and kind in ("added", "deleted", "typeChanged"):
            word += " folder"
        severity = flag["severity"] if flag else None
        why = (flag.get("reason") or flag.get("rule")) if flag else None
        if path in inside:
            count = inside[path]
            severity = severity or [name for name, value in SEVERITY_RANK.items() if value == group_rank[path]][0]
            held = "holds %d flagged %s, listed below it" % (count, "entry" if count == 1 else "entries")
            why = "%s; %s" % (why, held) if why else held
        yield row([severity, word, path, why, change.get("type"), change.get("size"),
                   change.get("previousSize"), covering(change), change.get("symlinkTarget"),
                   change.get("entriesInside")])


def undo_rows(data):
    data = need_object(data, "agent-vm session undo --json")
    restore = sub(data, "restore")
    restored = restore.get("restored") if isinstance(restore.get("restored"), list) else []
    failed = restore.get("failed") if isinstance(restore.get("failed"), dict) else {}
    yield row([len(restored), restore.get("remaining", 0), len(failed),
               "; ".join("%s: %s" % (path, reason) for path, reason in sorted(failed.items())),
               sub(data, "session").get("state")])


# -- A long command's stderr, as agentvm_job.py keeps it ----------------------------------
# Under --json, agent-vm writes one JSON event per line to stderr while it works, and a failure
# ends with "Error: <what failed and the fix>", possibly followed by more lines (a guest
# program's output). A crash or a signal can leave neither.

LOG_TAIL_BYTES = 1 << 20


def read_log(path):
    """(events, error lines, other lines) of a job log; only the last megabyte is read."""
    events, error, other = [], [], []
    with open(path, "rb") as log:
        log.seek(0, 2)
        size = log.tell()
        log.seek(max(0, size - LOG_TAIL_BYTES))
        data = log.read()
    if size > LOG_TAIL_BYTES:
        data = data.split(b"\n", 1)[1] if b"\n" in data else b""
    for line in data.decode("utf-8", errors="replace").splitlines():
        if error:
            error.append(line)
        elif line.startswith("Error: "):
            error.append(line[len("Error: "):])
        elif line.startswith("{"):
            try:
                event = json.loads(line)
            except ValueError:
                other.append(line)
                continue
            if isinstance(event, dict):
                events.append(event)
        elif line.strip():
            other.append(line)
    return events, error, other


def log_progress(path):
    """[step, fraction, message, notice]: the last progress event and the last notice."""
    events, _, _ = read_log(path)
    progress = [event for event in events if event.get("event") == "progress"]
    notices = [event for event in events if event.get("event") == "notice"]
    last = progress[-1] if progress else {}
    return [last.get("step"), last.get("fraction"), last.get("message"),
            notices[-1].get("message") if notices else None]


def log_error(path):
    """The error at the end of a job log, without "Error: ", as agent-vm wrote it (several
    lines when it wrote several). Without such a line, the last lines that are not events."""
    _, error, other = read_log(path)
    lines = error if error else other[-20:]
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


# -- An image recipe, for the New Image window -------------------------------------------

def recipe_rows(path):
    """A recipe file's description, inputs and parameters (see the docstring's "recipe")."""
    try:
        with open(path, encoding="utf-8") as source:
            recipe = json.load(source)
    except OSError as problem:
        raise ValueError(f"cannot read {path}: {problem.strerror}")
    recipe = need_object(recipe, path)
    tools = recipe.get("commandLineTools")
    yield row(["recipe", None, None, tools if isinstance(tools, bool) else None,
               recipe.get("description")])
    for name, spec in sub(recipe, "inputs").items():
        spec = spec if isinstance(spec, dict) else {}
        yield row(["input", name, True, None, spec.get("description")])
    for name, spec in sub(recipe, "parameters").items():
        spec = spec if isinstance(spec, dict) else {}
        has_default = "default" in spec
        yield row(["parameter", name, not has_default, spec.get("default") if has_default else None,
                   spec.get("description")])


COMMANDS = {"version": version_rows, "status": status_rows, "doctor": doctor_rows,
            "images": image_rows, "boxes": box_rows, "packs": pack_rows,
            "execlog": execlog_rows, "netlog": netlog_rows, "secrets": secret_rows,
            "sizes": size_rows, "sessions": session_rows, "report-summary": report_summary_rows,
            "changes": change_rows, "undo": undo_rows}


def main(argv):
    if len(argv) == 3 and argv[1] == "recipe":
        try:
            lines = list(recipe_rows(argv[2]))
        except (ValueError, UnicodeDecodeError) as problem:
            sys.stderr.write(f"agentvm_json.py recipe: {problem}\n")
            return 1
    elif len(argv) == 2 and argv[1] in COMMANDS:
        try:
            data = json.load(sys.stdin)
            lines = list(COMMANDS[argv[1]](data))
        except (ValueError, UnicodeDecodeError) as problem:
            sys.stderr.write(f"agentvm_json.py {argv[1]}: {problem}\n")
            return 1
    else:
        sys.stderr.write("usage: agentvm_json.py " + "|".join(COMMANDS) + " < agent-vm-output.json\n"
                         "       agentvm_json.py recipe <recipe.json>\n")
        return 2
    for line in lines:
        sys.stdout.write(line + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
