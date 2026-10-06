#!/usr/bin/env python3
# sandbox_packs.py
# SANDBOX PACKS: named sets of folders for one kind of work on this Mac (building with Xcode,
# Homebrew's tools, git), ticked as a whole instead of adding each folder a tool is refused.
# This file reads packs, checks them, and turns the ticked ones into the folders the Local
# server's sandbox is given. generate_mcp_configs.py imports it; run as a program it lists every
# pack with what it would grant here, for the windows that show packs.
#
# Usage: python3 sandbox_packs.py list --bundle <Cadabra.app> [--user-dir DIR] [--project DIR]
#                                      [--token NAME=VALUE ...]
#        python3 sandbox_packs.py check <pack.json> [--project DIR] [--token NAME=VALUE ...]
#   list   prints a JSON array, one object per pack (PackResult.as_json), seed packs first.
#   check  prints the same object for one file wherever it is; its status is 0 when the pack is
#          usable here, 1 when it is not installed or invalid.
#   --token gives a token's value instead of asking this Mac for it (tests, and trying a pack
#   for another setup). The generator never passes it.
#
# A PACK is one JSON file, <id>.json:
#   {
#     "formatVersion": 1,
#     "id": "xcode",                            lowercase letters, digits and "-"; the file's name
#     "title": "Xcode and Swift builds",
#     "description": "Build and test with xcodebuild and swift.",
#     "read_only":  ["$DEVELOPER_DIR", ...],    folders: everything under each can be read
#     "read_write": ["~/Library/Developer/Xcode/DerivedData", ...],   folders: read and written
#     "read_only_files": ["~/.gitconfig"],      single files that can be read
#     "requires": ["$DEVELOPER_DIR"],           what must exist for the pack to be usable here
#     "notes": ["What the pack does not cover."],
#     "recorded": { ... }                       how the pack was made; not read here
#   }
# Unknown keys are ignored. A pack holds no sandbox rules, no service names and no network
# setting: only folders, and files to read.
#
# A path is absolute, or starts with one TOKEN, given its value when the packs are resolved:
#   ~                        the home folder
#   $DEVELOPER_DIR           xcode-select -p, up to the .app when it is inside one
#   $HOMEBREW_PREFIX         /opt/homebrew or /usr/local, whichever has bin/brew
#   $DARWIN_USER_CACHE_DIR   getconf DARWIN_USER_CACHE_DIR
#   $DARWIN_USER_TEMP_DIR    getconf DARWIN_USER_TEMP_DIR
#   $PROJECT                 the session's Project folder
# A token with no value here drops the paths that use it. An unknown token makes the pack invalid.
#
# SEED PACKS ship in the application (Contents/Resources/SandboxPacks); USER PACKS are in
# Application Support/Cadabra/SandboxPacks, and one with a seed pack's id replaces it.
#
# WHAT A PACK CAN NEVER GRANT (NEVER_GRANT below): the folders that hold keys, mail, messages,
# browser data and Cadabra's own data, anything inside one, and any folder that contains one,
# which covers the home folder, its Library and "/". A pack that names such a path is invalid as
# a whole and grants nothing: a pack that asks for one is not a pack to trust with the rest.
#
# WHAT IS GRANTED is the path's true name on disk (links followed, the spelling the disk has),
# and only for what exists now. A read-write folder that is a link, or is reached through one,
# is left out: a tool that may write a folder can replace it with a link, and the next session
# would otherwise follow that link wherever it points.

import argparse
import fcntl
import functools
import json
import os
import re
import stat
import subprocess
import sys

FORMAT_VERSION = 1
SEED_DIR_IN_BUNDLE = "Contents/Resources/SandboxPacks"
USER_DIR_NAME = "SandboxPacks"
PREFS_KEY = "packs"

TOKENS = ("DEVELOPER_DIR", "HOMEBREW_PREFIX", "DARWIN_USER_CACHE_DIR", "DARWIN_USER_TEMP_DIR", "PROJECT")
_ID_PATTERN = re.compile(r"[a-z0-9][a-z0-9-]{0,63}\Z")
_TOKEN_PATTERN = re.compile(r"\$([A-Z_]+)(/.*)?\Z", re.DOTALL)
_MAX_PACK_BYTES = 256 * 1024
_MAX_PATHS = 200

# Relative to the home folder. A pack may not name one of these, anything inside one, or a folder
# that contains one.
NEVER_GRANT = (
    ".ssh", ".aws", ".azure", ".gnupg", ".kube", ".docker", ".netrc", ".git-credentials",
    ".config/gh", ".config/gcloud", ".config/op", ".config/git/credentials",
    "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Cookies", "Library/Safari",
    "Library/Accounts", "Library/Calendars", "Library/Application Support/AddressBook",
    "Library/Application Support/com.apple.TCC",
    "Library/Application Support/Cadabra",
    "Library/Application Support/Google/Chrome", "Library/Application Support/Firefox",
    "Library/Application Support/Microsoft Edge", "Library/Application Support/BraveSoftware",
    "Library/Application Support/Arc", "Library/Application Support/Chromium",
    "Library/Application Support/1Password", "Library/Group Containers", "Library/Containers",
)


def is_pack_id(text):
    """True for text that can be a pack's id: lowercase letters, digits and "-"."""
    return isinstance(text, str) and bool(_ID_PATTERN.match(text))


class PackError(Exception):
    """Why a pack file is not a pack. The text is shown to the user."""


def true_path(path):
    """The name the disk has for an existing path (links followed, its own spelling), or ""."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except (OSError, ValueError):
        # ValueError: a NUL or a character with no UTF-8 form; no file has such a name.
        return ""
    try:
        raw = fcntl.fcntl(fd, fcntl.F_GETPATH, b"\0" * 1024)
    except OSError:
        return ""
    finally:
        os.close(fd)
    try:
        return raw.split(b"\0", 1)[0].decode("utf-8")
    except UnicodeDecodeError:
        return ""


def _plain(path):
    """A path with "." parts, doubled and trailing slashes removed. ".." is refused earlier."""
    # normpath keeps exactly two leading slashes, which would pass every comparison below.
    return os.path.normpath("/" + path.lstrip("/")) if path.startswith("/") else os.path.normpath(path)


def _within(path, folder):
    """True when path is folder or inside it. Both plain; compared without regard to case, as the
    disk compares names."""
    path = path.casefold()
    folder = folder.casefold()
    if folder == "/":
        return True
    return path == folder or path.startswith(folder + "/")


def _run_line(argv):
    """The first line a system tool prints, or ""."""
    try:
        done = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return ""
    if done.returncode != 0:
        return ""
    lines = done.stdout.decode("utf-8", "replace").splitlines()
    return lines[0].strip() if lines else ""


def _up_to_app(path):
    """A developer folder inside an application is that application: Xcode's tools read more of
    Xcode.app than its Contents/Developer."""
    at = path.find(".app/")
    return path[:at + 4] if at >= 0 else path


def _homebrew_prefix():
    for prefix in ("/opt/homebrew", "/usr/local"):
        if os.path.isfile(prefix + "/bin/brew"):
            return prefix
    return ""


def token_values(project="", given=None):
    """Every token's value on this Mac, as a true path, "" when it has none. `given` (a dict)
    replaces what this Mac would answer, name by name."""
    given = given or {}
    askers = {
        "HOME": lambda: os.path.expanduser("~"),
        "DEVELOPER_DIR": lambda: _run_line(["/usr/bin/xcode-select", "-p"]),
        "HOMEBREW_PREFIX": _homebrew_prefix,
        "DARWIN_USER_CACHE_DIR": lambda: _run_line(["/usr/bin/getconf", "DARWIN_USER_CACHE_DIR"]),
        "DARWIN_USER_TEMP_DIR": lambda: _run_line(["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"]),
        "PROJECT": lambda: project,
    }
    values = {}
    for name, ask in askers.items():
        value = given[name] if name in given else ask()
        value = (value or "").strip()
        if name == "DEVELOPER_DIR":
            value = _up_to_app(value)
        values[name] = true_path(value) if value.startswith("/") else ""
    return values


def _expand(path, values):
    """(the path with its token replaced, "") or ("", why not). Raises PackError for a path no
    pack may hold whatever this Mac is like."""
    if not isinstance(path, str) or not path or len(path) > 1024:
        raise PackError("a path is not text, is empty or is too long")
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in path):
        raise PackError("a path has a control character")
    # Half of a UTF-16 pair, which JSON can spell (\ud800): no file has such a name, and it
    # cannot be written to the log.
    if any(0xD800 <= ord(ch) <= 0xDFFF for ch in path):
        raise PackError("a path has a character that is not text")
    if ".." in path.split("/"):
        raise PackError(f'"{path}" has a ".." part')
    if path == "~" or path.startswith("~/"):
        name, rest = "HOME", path[1:]
    elif path.startswith("$"):
        match = _TOKEN_PATTERN.match(path)
        if not match or match.group(1) not in TOKENS:
            raise PackError(f'"{path}" starts with a token this version does not know')
        name, rest = match.group(1), match.group(2) or ""
    elif path.startswith("/"):
        return _plain(path), ""
    else:
        raise PackError(f'"{path}" is neither absolute nor starts with a token')
    base = values.get(name, "")
    if not base:
        return "", "~ has no value here" if name == "HOME" else f"${name} has no value here"
    return _plain(base + rest), ""


def _without_data_volume(path):
    """The disk's data volume holds everything under a second name; this is the first."""
    alias = "/System/Volumes/Data"
    return (path[len(alias):] or "/") if _within(path, alias) else path


@functools.lru_cache(maxsize=8)
def _guarded(home):
    """((entry, folder), ...) for NEVER_GRANT: each folder as named under the home folder and,
    when that name is a link or passes through one (~/.aws kept in a dotfiles folder), the
    folder it leads to as well. Without the second, a pack could name the place the keys really
    are. Found with lstat and readlink, which do not open the folders: opening Mail or Messages
    would be refused by macOS and could ask the user."""
    found = []
    for entry in NEVER_GRANT:
        named = home + "/" + entry
        found.append((entry, named))
        try:
            led = _without_data_volume(os.path.realpath(named))
        except (OSError, ValueError):
            continue
        if led != named:
            found.append((entry, led))
    return tuple(found)


def guarded_place(path, home):
    """What a plain absolute path has to do with the guarded folders: None when nothing, or
    (kind, entry) with kind "disk" (the whole disk), "no-home" (the home folder cannot be found,
    so nothing can be checked), "home" (the home folder or a folder that contains it), "in" (in
    the NEVER_GRANT folder `entry`) or "contains" (contains it). entry is "" for the first three."""
    path = _without_data_volume(path)
    if path.casefold() in ("/", "/system", "/system/volumes"):
        return "disk", ""
    if not home:
        return "no-home", ""
    if _within(home, path):
        return "home", ""
    for entry, guarded in _guarded(home):
        if _within(path, guarded):
            return "in", entry
        if _within(guarded, path):
            return "contains", entry
    return None


def never_grant_reason(path, home):
    """Why a plain absolute path can never be granted by a pack, or ""."""
    place = guarded_place(path, home)
    if place is None:
        return ""
    kind, entry = place
    return {
        "disk": "it contains the whole disk",
        "no-home": "the home folder cannot be found, so nothing can be checked against it",
        "home": "it is the home folder or contains it",
        "in": f"it is in ~/{entry}, which no pack may open",
        "contains": f"it contains ~/{entry}, which no pack may open",
    }[kind]


class PackResult:
    """One pack, read and resolved for this Mac.

    state: "ok" (usable), "not-installed" (something it requires is missing), "invalid".
    read_only / read_write / read_only_files: what it grants here, true paths. Empty unless ok.
    dropped: [(path as written, reason)] of an ok pack: named but not granted here.
    """

    def __init__(self, pack_id, source, path):
        self.id = pack_id
        self.source = source
        self.path = path
        self.title = pack_id
        self.description = ""
        self.notes = []
        self.state = "invalid"
        self.reason = ""
        self.read_only = []
        self.read_write = []
        self.read_only_files = []
        self.dropped = []

    def as_json(self):
        return {
            "id": self.id, "source": self.source, "path": self.path, "title": self.title,
            "description": self.description, "notes": self.notes, "state": self.state,
            "reason": self.reason, "read_only": self.read_only, "read_write": self.read_write,
            "read_only_files": self.read_only_files,
            "dropped": [{"path": path, "reason": reason} for path, reason in self.dropped],
        }


def _string_list(pack, key):
    value = pack.get(key, [])
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise PackError(f'"{key}" is not a list of text')
    if len(value) > _MAX_PATHS:
        raise PackError(f'"{key}" has more than {_MAX_PATHS} entries')
    return value


def _resolve_into(result, pack, values):
    """Fills result from the pack's content. Raises PackError when the pack is invalid."""
    if not isinstance(pack, dict):
        raise PackError("the file is not a JSON object")
    version = pack.get("formatVersion")
    if not isinstance(version, int) or isinstance(version, bool) or version < 1:
        raise PackError('"formatVersion" is missing or is not a number')
    if version > FORMAT_VERSION:
        raise PackError("it was made for a newer Cadabra")
    if pack.get("id") != result.id:
        raise PackError(f'its "id" is not its file\'s name ("{result.id}")')
    title = pack.get("title")
    if not isinstance(title, str) or not title.strip() or len(title) > 100:
        raise PackError('"title" is missing, empty or too long')
    description = pack.get("description", "")
    if not isinstance(description, str) or len(description) > 1000:
        raise PackError('"description" is not text or is too long')
    result.title = title.strip()
    result.description = description.strip()
    result.notes = [note.strip() for note in _string_list(pack, "notes") if note.strip()]

    home = values.get("HOME", "")
    read_only, read_write, files, dropped = [], [], [], []
    # Read-write first, so a folder in both lists is granted once, read-write.
    for key in ("read_write", "read_only", "read_only_files"):
        for written in _string_list(pack, key):
            path, why = _expand(written, values)
            if not path:
                dropped.append((written, why))
                continue
            # Checked as written and, below, as the disk names it: the first refuses a pack
            # that names a guarded folder this Mac does not have (yet), the second a link to one.
            refusal = never_grant_reason(path, home)
            if refusal:
                raise PackError(f'"{written}" cannot be granted: {refusal}')
            real = true_path(path)
            if not real:
                dropped.append((written, "not on this Mac"))
                continue
            refusal = never_grant_reason(real, home)
            if refusal:
                raise PackError(f'"{written}" cannot be granted: {refusal}')
            try:
                kind = os.stat(real).st_mode
            except OSError:
                dropped.append((written, "not on this Mac"))
                continue
            if key == "read_only_files":
                if not stat.S_ISREG(kind):
                    dropped.append((written, "not a file"))
                elif real not in files:
                    files.append(real)
                continue
            if not stat.S_ISDIR(kind):
                dropped.append((written, "not a folder"))
                continue
            if key == "read_write":
                if real != path:
                    dropped.append((written, "a link, or reached through one: not granted for writing"))
                elif real not in read_write:
                    read_write.append(real)
            elif real not in read_write and real not in read_only:
                read_only.append(real)

    for written in _string_list(pack, "requires"):
        path, why = _expand(written, values)
        if not path or not os.path.exists(path):
            result.state = "not-installed"
            result.reason = f"{written} is not on this Mac"
            return
    result.state = "ok"
    result.read_only, result.read_write, result.read_only_files = read_only, read_write, files
    result.dropped = dropped


def load_pack(path, source, values):
    """The pack in a file, as a PackResult; an unreadable or wrong file gives an invalid one."""
    name = os.path.basename(path)
    result = PackResult(name[:-5] if name.endswith(".json") else name, source, path)
    try:
        if not is_pack_id(result.id):
            raise PackError("its file name is not a pack id (lowercase letters, digits and -)")
        with open(path, "rb") as fh:
            raw = fh.read(_MAX_PACK_BYTES + 1)
        if len(raw) > _MAX_PACK_BYTES:
            raise PackError("the file is too large to be a pack")
        _resolve_into(result, json.loads(raw.decode("utf-8")), values)
    except PackError as e:
        result.reason = str(e)
    except (OSError, ValueError, RecursionError) as e:
        result.reason = f"the file cannot be read as a pack ({e})"
    return result


def _pack_files(folder):
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    return [os.path.join(folder, name) for name in names
            if name.endswith(".json") and not name.startswith(".")]


def all_packs(bundle, user_dir="", project="", given_tokens=None):
    """Every pack, as PackResults: seed packs in name order, then the user's own. A user pack
    with a seed pack's id takes its place, also when it is invalid."""
    values = token_values(project, given_tokens)
    packs = {}
    for path in _pack_files(os.path.join(bundle, SEED_DIR_IN_BUNDLE)):
        pack = load_pack(path, "seed", values)
        packs[pack.id] = pack
    if user_dir:
        for path in _pack_files(user_dir):
            pack = load_pack(path, "user", values)
            packs[pack.id] = pack
    return list(packs.values())


def sourced_grants(ticked, packs):
    """What the ticked ones of `packs` (PackResults) grant, with the packs each path comes from:
    (read_only, read_write, read_only_files, messages). The first three are dicts in the order
    granted, true path -> [pack title, ...]; a folder some pack grants read-write is left out of
    read_only. messages has a line for each ticked pack that grants nothing, and for each path
    of a usable one that is left out."""
    read_only, read_write, files, messages = {}, {}, {}, []
    by_id = {pack.id: pack for pack in packs}
    for pack_id in ticked_ids(ticked):
        pack = by_id.get(pack_id)
        if pack is None:
            messages.append(f"sandbox pack {pack_id!r} is ticked but there is no such pack")
            continue
        if pack.state != "ok":
            messages.append(f"sandbox pack {pack_id!r} grants nothing: {pack.reason}")
            continue
        for written, reason in pack.dropped:
            messages.append(f"sandbox pack {pack_id!r}: {written} left out ({reason})")
        for granted, paths in ((read_write, pack.read_write), (read_only, pack.read_only),
                               (files, pack.read_only_files)):
            for path in paths:
                granted.setdefault(path, []).append(pack.title)
    for path in read_write:
        read_only.pop(path, None)
    return read_only, read_write, files, messages


def ticked_ids(ticked):
    """The pack ids in a stored list of ticked packs, each once; [] for anything that is not a
    list (a hand-edited settings file)."""
    wanted = []
    if isinstance(ticked, list):
        for pack_id in ticked:
            if isinstance(pack_id, str) and pack_id not in wanted:
                wanted.append(pack_id)
    return wanted


def grants(ticked, bundle, user_dir="", project="", given_tokens=None):
    """What the ticked packs grant here: (read_only, read_write, read_only_files, messages).
    The lists are true paths without repeats, a folder some pack grants read-write left out of
    read_only. messages is sourced_grants'."""
    if not ticked_ids(ticked):
        # Nothing ticked, which is most sessions: no pack is read and no tool is asked.
        return [], [], [], []
    read_only, read_write, files, messages = sourced_grants(
        ticked, all_packs(bundle, user_dir, project, given_tokens))
    return list(read_only), list(read_write), list(files), messages


def _given_tokens(words):
    given = {}
    for word in words or []:
        name, sep, value = word.partition("=")
        if not sep or (name not in TOKENS and name != "HOME"):
            sys.exit(f"sandbox_packs: --token wants NAME=VALUE with a known name, not {word!r}")
        given[name] = value
    return given


def main(argv):
    parser = argparse.ArgumentParser(prog="sandbox_packs.py", allow_abbrev=False)
    commands = parser.add_subparsers(dest="command", required=True)
    lister = commands.add_parser("list", allow_abbrev=False)
    lister.add_argument("--bundle", required=True)
    lister.add_argument("--user-dir", default="")
    checker = commands.add_parser("check", allow_abbrev=False)
    checker.add_argument("file")
    for sub in (lister, checker):
        sub.add_argument("--project", default="")
        sub.add_argument("--token", action="append")
    options = parser.parse_args(argv)
    given = _given_tokens(options.token)
    if options.command == "list":
        packs = all_packs(options.bundle, options.user_dir, options.project, given)
        json.dump([pack.as_json() for pack in packs], sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    pack = load_pack(options.file, "file", token_values(options.project, given))
    json.dump(pack.as_json(), sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0 if pack.state == "ok" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
