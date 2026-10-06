#!/usr/bin/env python3
# sandbox_packs_record.py
# RECORDING A SANDBOX PACK: a command is run under a sandbox that grants almost nothing, what it
# is refused is granted and it is run again, until it succeeds. The folders found are reviewed
# by the user and saved as a pack (sandbox_packs.py). The running is replay's
# sandbox-discover.py (--loop --json); this file drives it for the Record a Pack window, keeps
# what was found in a state file of the window's own, and writes the pack.
#
# Usage: python3 sandbox_packs_record.py run --discover <sandbox-discover.py> --folder <dir>
#                                            --state <file> --pid-file <file> -- <command line>
#        python3 sandbox_packs_record.py rows --state <file>
#        python3 sandbox_packs_record.py keep --state <file> --row <index>
#        python3 sandbox_packs_record.py access --state <file> --row <index>
#        python3 sandbox_packs_record.py slug --title <text>
#        python3 sandbox_packs_record.py save --state <file> --user-dir <dir> --id <id>
#                                             --title <text> [--description <text>]
#                                             [--seed-dir <dir>] [--replace]
#
#   run     runs the command line with /bin/sh in the folder, which is granted from the start
#           (a session's project always is) and is left out of what is found, as are the
#           system folders replay's sandbox always allows, and devices. Prints one line
#           per step, tab separated, for the window:
#               pass <number> <command's exit status> <folders found so far>
#               check <path being checked>
#               end <outcome> <message>
#           outcome is "success" (the command ran), "partial" (it still fails; what was found is
#           kept for review), or "failed" (nothing to review). The state file is written before
#           the end line. Its own process id is in --pid-file while it runs; ended with SIGTERM
#           it stops the command and everything the command started.
#   rows    prints the review table: a checkbox image name, the path as the pack would hold it,
#           the access in words, a note.
#   keep    ticks or unticks a row (0-based). A row that can never be in a pack stays unticked.
#   access  switches a folder row between reading and reading and changing.
#   slug    prints a pack id made from a title.
#   save    writes <user-dir>/<id>.json from the ticked rows and prints its path. Status 2,
#           with what it would replace on standard error, when --replace was not given and a
#           pack with that id is already there: one of the user's own, or one in --seed-dir (the
#           packs that come with the application), whose place a user pack with its id takes.
#           1, with the reason on standard error, for anything else that keeps the pack from
#           being written.
#
# A STATE FILE is {"command", "folder", "outcome", "rows": [row, ...]}; a row is
#   {"path": the true path found, "written": the same with a token where one fits,
#    "access": "read_write" | "read_only" | "file", "keep": bool, "locked": bool, "note": text}
# A locked row is one no pack may hold; it is shown so the user knows the command touched it.

import argparse
import datetime
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time

import sandbox_packs

TICKED_IMAGE = "checkmark.square.fill"
UNTICKED_IMAGE = "square"
LOCKED_IMAGE = "minus.square"
ACCESS_WORDS = {"read_write": "Read and change", "read_only": "Read", "file": "Read (one file)"}

# Folders too wide to keep without a second look: everything inside belongs to many programs.
_WIDE_IN_HOME = ("Library/Application Support", "Library/Caches", "Library/Preferences",
                 "Library/Developer", "Documents", "Desktop", "Downloads")


# What replay's sandbox always lets a tool read (its baseline), and devices: found because the
# recorder's sandbox is narrower than a session's, and of no use in a pack.
_ALWAYS_ALLOWED = ("/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/lib", "/System/Library", "/dev")


def _one_line(text):
    return " ".join("".join(ch if ch.isprintable() else " " for ch in str(text)).split())


def _within(path, folder):
    return path == folder or path.startswith(folder.rstrip("/") + "/")


def tokenized(path, values):
    """The path as a pack holds it: with the token whose folder is the longest one it is in."""
    best_name, best_base = "", ""
    for name, base in values.items():
        if name == "PROJECT" or not base or base == "/":
            continue
        if _within(path, base) and len(base) > len(best_base):
            best_name, best_base = name, base
    if not best_base:
        return path
    rest = path[len(best_base):]
    return ("~" if best_name == "HOME" else "$" + best_name) + rest


def review_rows(done, folder, values):
    """The rows for a recorder's `done` event (read_only, read_write, folder_only, unverified).
    The run's own folder and what is inside it are left out."""
    home = values.get("HOME", "")
    wide = {home + "/" + name for name in _WIDE_IN_HOME} if home else set()
    unverified = set(done.get("unverified") or [])
    rows = []
    seen = set()

    def add(path, access, locked_note=""):
        if not isinstance(path, str) or not path.startswith("/"):
            return
        if any(_within(path, always) for always in _ALWAYS_ALLOWED):
            return
        reported = path
        place = sandbox_packs.guarded_place(path, home)
        if place is None:
            # The name the disk has: the recorder follows links but keeps the spelling it was
            # given, and a pack's reader grants a folder to change only under its true name.
            # Not asked for a guarded folder, which macOS may refuse to open, or ask about.
            path = sandbox_packs.true_path(path) or path
            place = sandbox_packs.guarded_place(path, home)
        if path in seen:
            return
        if folder and _within(path, folder):
            return
        if any(_within(path, always) for always in _ALWAYS_ALLOWED):
            return
        seen.add(path)
        row = {"path": path, "written": tokenized(path, values), "access": access,
               "keep": True, "locked": False, "note": ""}
        if locked_note:
            row.update(access="read_only", keep=False, locked=True, note=locked_note)
        elif place is not None:
            kind, entry = place
            why = {"disk": "the whole disk", "home": "the home folder, or a folder that contains it",
                   "no-home": "cannot be checked: the home folder was not found",
                   "in": f"in ~/{entry}, which holds keys or private data",
                   "contains": f"contains ~/{entry}, which holds keys or private data"}[kind]
            row.update(keep=False, locked=True, note="Never in a pack: " + why)
        elif access == "read_write" and os.path.isfile(path):
            row.update(keep=False, locked=True, note="A single file to change cannot be in a pack")
        elif os.path.isfile(path):
            row["access"] = "file"
        elif not os.path.isdir(path):
            row.update(keep=False, locked=True, note="Neither a folder nor a file on this Mac now")
        elif path in wide or (home and os.path.dirname(path) == home):
            row.update(keep=False, note="Wide: holds the data of many programs. Keep it only if nothing narrower works")
        if not row["locked"] and reported in unverified:
            row["note"] = _one_line("Unverified: may have been refused to another program. " + row["note"])
        rows.append(row)

    for path in done.get("read_write") or []:
        add(path, "read_write")
    for path in done.get("read_only") or []:
        add(path, "read_only")
    for path in done.get("folder_only") or []:
        add(path, "read_only", "Only the folder's own listing was needed, which a pack cannot grant")
    return rows


def _write_state(path, state):
    scratch = path + ".new"
    with open(scratch, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    os.replace(scratch, path)


def _read_state(path):
    with open(path, "rb") as fh:
        state = json.load(fh)
    if not isinstance(state, dict) or not isinstance(state.get("rows"), list):
        raise ValueError("not a recording's state file")
    return state


def _say(*fields):
    print("\t".join(_one_line(field) for field in fields), flush=True)


def _end_group(group, patience=2.0):
    """After the recorder was ended with SIGTERM: what is still running in its process group when
    the patience is over is killed. A command that ignores SIGTERM would otherwise run on, with
    no window left to stop it."""
    deadline = time.monotonic() + patience
    while time.monotonic() < deadline:
        try:
            os.killpg(group, 0)
        except OSError:
            return
        time.sleep(0.1)
    try:
        os.killpg(group, signal.SIGKILL)
    except OSError:
        pass


def run(options):
    command = " ".join(options.command).strip()
    folder = sandbox_packs.true_path(options.folder)
    state = {"command": command, "folder": folder, "outcome": "failed", "rows": []}
    if not command or not folder or not os.path.isdir(folder):
        _write_state(options.state, state)
        _say("end", "failed", "There is no command, or the folder to run it in is not a folder.")
        return 0
    if not os.path.isfile(options.discover):
        _write_state(options.state, state)
        _say("end", "failed", "The recorder (sandbox-discover.py) is not in this copy of Cadabra.")
        return 0

    profile = options.state + ".profile.json"
    # Absolute, since the recorder runs in the command's folder.
    argv = [os.path.abspath(sys.executable), "-B", os.path.abspath(options.discover),
            "--loop", "--json", "-o", os.path.abspath(profile),
            "--allow-write", folder, "--", "/bin/sh", "-c", command]
    child = None
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True
        if child is not None:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except OSError:
                pass

    # Before the recorder is started: a signal that comes while it starts is kept, not lost
    # with the recorder left running.
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    done = None
    said = ""
    try:
        with open(options.pid_file, "w", encoding="utf-8") as fh:
            fh.write(f"{os.getpid()}\n")
        # A session of its own, so stopping takes the command and all it started, and nothing else.
        child = subprocess.Popen(argv, cwd=folder, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.PIPE, start_new_session=True)
        if stopping:
            stop(None, None)
        for raw in child.stderr:
            text = raw.decode("utf-8", "replace")
            try:
                event = json.loads(text)
            except ValueError:
                # Not an event: the recorder's own complaint, kept for the message below.
                said = _one_line(text)[:300] or said
                continue
            if not isinstance(event, dict):
                continue
            kind = event.get("event")
            if kind == "pass":
                found = len(event.get("read_only") or []) + len(event.get("read_write") or [])
                _say("pass", event.get("pass", ""), event.get("exit", ""), found)
            elif kind == "check":
                without = event.get("without", "")
                _say("check", ", ".join(map(str, without)) if isinstance(without, list) else without)
            elif kind == "done":
                done = event
        child.wait()
        if stopping:
            _end_group(child.pid)
    finally:
        for leftover in (options.pid_file, profile):
            try:
                os.remove(leftover)
            except OSError:
                pass

    if done is None:
        _write_state(options.state, state)
        if child.returncode is not None and child.returncode < 0:
            _say("end", "failed", "Recording was stopped. Nothing was kept.")
        else:
            _say("end", "failed", "The recorder ended without a result. Nothing was kept."
                 + (f" It said: {said}" if said else ""))
        return 0
    state["rows"] = review_rows(done, folder, sandbox_packs.token_values())
    stopped = done.get("stopped")
    if stopped == "success":
        state["outcome"] = "success"
        message = f"The command ran after {done.get('passes', '?')} passes."
    else:
        state["outcome"] = "partial"
        why = "the passes ran out" if stopped == "max-passes" else "nothing more was refused"
        message = (f"The command still fails (status {done.get('exit', '?')}) and {why}. "
                   "A folder may not be what it lacks: a system service, the network, or a tool that "
                   "starts a sandbox of its own.")
    if not state["rows"]:
        message += " It needed no folder beyond its own."
    _write_state(options.state, state)
    _say("end", state["outcome"], message)
    return 0


def rows(options):
    for row in _read_state(options.state)["rows"]:
        image = LOCKED_IMAGE if row["locked"] else TICKED_IMAGE if row["keep"] else UNTICKED_IMAGE
        _say(image, row["written"], ACCESS_WORDS[row["access"]], row["note"])
    return 0


def _change_row(options, change):
    state = _read_state(options.state)
    if 0 <= options.row < len(state["rows"]):
        row = state["rows"][options.row]
        if not row["locked"]:
            change(row)
            _write_state(options.state, state)
    return 0


def keep(options):
    def change(row):
        row["keep"] = not row["keep"]
    return _change_row(options, change)


def access(options):
    def change(row):
        if row["access"] in ("read_only", "read_write"):
            row["access"] = "read_write" if row["access"] == "read_only" else "read_only"
    return _change_row(options, change)


def slug_of(title):
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:64].strip("-")
    return slug


def slug(options):
    print(slug_of(options.title))
    return 0


def save(options):
    state = _read_state(options.state)
    title = _one_line(options.title)
    if not title or len(title) > 100:
        print("The pack needs a title of at most 100 characters.", file=sys.stderr)
        return 1
    if not sandbox_packs.is_pack_id(options.id):
        print("The pack's id may hold only lowercase letters, digits and \"-\", and must start with a letter or a digit.", file=sys.stderr)
        return 1
    kept = [row for row in state["rows"] if row["keep"] and not row["locked"]]
    if not kept:
        print("No folder is ticked, so there is nothing to put in a pack.", file=sys.stderr)
        return 1
    path = os.path.join(options.user_dir, options.id + ".json")
    if not options.replace:
        if os.path.lexists(path):
            print("A pack of your own with this id is already there. Replacing it changes what "
                  "every session that uses it is allowed.", file=sys.stderr)
            return 2
        if options.seed_dir and os.path.lexists(os.path.join(options.seed_dir, options.id + ".json")):
            print("A pack that comes with Cadabra has this id. A pack of your own with the same id "
                  "takes its place in every session, until you remove yours.", file=sys.stderr)
            return 2
    pack = {
        "formatVersion": sandbox_packs.FORMAT_VERSION,
        "id": options.id,
        "title": title,
        "description": _one_line(options.description)[:1000],
        "read_only": [row["written"] for row in kept if row["access"] == "read_only"],
        "read_write": [row["written"] for row in kept if row["access"] == "read_write"],
        "read_only_files": [row["written"] for row in kept if row["access"] == "file"],
        "recorded": {"by": "sandbox-discover", "command": state.get("command", ""),
                     "date": datetime.date.today().isoformat()},
    }
    # Read as the application will read it, before it takes the place of anything.
    checked = sandbox_packs.pack_from_content(options.id, pack, sandbox_packs.token_values())
    if checked.state == "invalid":
        print(f"The pack could not be made: {checked.reason}.", file=sys.stderr)
        return 1
    os.makedirs(options.user_dir, exist_ok=True)
    # A new file under a name nothing else has, so no link left in the folder is written through;
    # removed when it cannot take the pack's place (a folder is there under that name).
    handle, scratch = tempfile.mkstemp(prefix=options.id + ".", suffix=".new", dir=options.user_dir)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as fh:
            json.dump(pack, fh, indent=2)
            fh.write("\n")
        os.chmod(scratch, 0o644)
        os.replace(scratch, path)
    except OSError:
        try:
            os.remove(scratch)
        except OSError:
            pass
        raise
    print(path)
    return 0


def main(argv):
    parser = argparse.ArgumentParser(prog="sandbox_packs_record.py", allow_abbrev=False)
    commands = parser.add_subparsers(dest="command_name", required=True)
    runner = commands.add_parser("run", allow_abbrev=False)
    for option in ("--discover", "--folder", "--state", "--pid-file"):
        runner.add_argument(option, required=True)
    runner.add_argument("command", nargs=argparse.REMAINDER)
    for name in ("rows", "keep", "access"):
        sub = commands.add_parser(name, allow_abbrev=False)
        sub.add_argument("--state", required=True)
        if name != "rows":
            sub.add_argument("--row", type=int, required=True)
    slugger = commands.add_parser("slug", allow_abbrev=False)
    slugger.add_argument("--title", required=True)
    saver = commands.add_parser("save", allow_abbrev=False)
    for option in ("--state", "--user-dir", "--id", "--title"):
        saver.add_argument(option, required=True)
    saver.add_argument("--description", default="")
    saver.add_argument("--seed-dir", default="")
    saver.add_argument("--replace", action="store_true")
    options = parser.parse_args(argv)
    if options.command_name == "run" and options.command[:1] == ["--"]:
        options.command = options.command[1:]
    handlers = {"run": run, "rows": rows, "keep": keep, "access": access, "slug": slug, "save": save}
    try:
        return handlers[options.command_name](options)
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"sandbox_packs_record: {options.command_name}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
