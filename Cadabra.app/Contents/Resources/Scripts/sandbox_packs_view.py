#!/usr/bin/env python3
# sandbox_packs_view.py
# What Agentic Session Tools shows of the sandbox packs (sandbox_packs.py): the two tables of
# granted folders, with where each comes from, and the Choose Packs sheet, a list of packs with a
# checkbox each beside a preview of what the selected pack holds. The handlers
# (aichat.mcp.servers.packs*.sh) run this and pass what it prints to the window.
#
# Usage: python3 sandbox_packs_view.py pane --prefs <settings.plist> --bundle <Cadabra.app>
#                                           --out <prefix> [--session-tmpdir DIR]
#        python3 sandbox_packs_view.py open --prefs <settings.plist> --bundle <Cadabra.app>
#                                           --list <file> --ticked <file>
#        python3 sandbox_packs_view.py rows --list <file> --ticked <file>
#        python3 sandbox_packs_view.py toggle --list <file> --ticked <file> --row <index>
#        python3 sandbox_packs_view.py preview --list <file> --id <pack id>
#        python3 sandbox_packs_view.py chosen --list <file> --ticked <file>
#
#   pane     writes three files for the pane: <prefix>.rw.tsv and <prefix>.ro.tsv, the rows of the
#            read-write and read-only tables (path, From, and a hidden kind: "user" for a folder
#            of the user's own list, "session" for the session's temporary folder, "pack" for one
#            only a pack grants), and <prefix>.summary, the ticked packs' titles on one line.
#   open     starts the sheet: writes every pack as resolved now to --list (sandbox_packs.py's
#            list) and the stored ticked ids, one per line, to --ticked. The ticks are a draft in
#            that file until the sheet's button stores them.
#   rows     prints the sheet's table: a checkbox image name, the pack's title, its id (hidden).
#   toggle   ticks or unticks the pack in a row (0-based) of that table and prints its id. A pack
#            that cannot be used here can be unticked but not ticked.
#   preview  prints Markdown for one pack: what it grants here, what it leaves out, its notes.
#   chosen   prints the ids to store, one per line: the draft's, without ids no pack has.
#            Each is a pack id as sandbox_packs.py defines one, so a line is one word.
#
# The sheet works from the --list file, so the rows, the preview and what is stored agree with
# each other however long the sheet is open.

import argparse
import json
import os
import plistlib
import sys
import unicodedata

import sandbox_packs

FROM_USER = "You"
FROM_SESSION = "This session"
TICKED_IMAGE = "checkmark.square.fill"
UNTICKED_IMAGE = "square"
UNUSABLE_IMAGE = "minus.square"


def _one_line(text):
    """Text for a table cell or one line of a file: no tab, line end or other control character."""
    return " ".join("".join(ch if ch.isprintable() else " " for ch in text).split())


def _stored_path(text):
    """One of the user's own folders for a table cell, as stored but for what would break the row
    (a tab, a line end, another control character): the - button removes the entry whose text is
    the cell's, so doubled spaces and other spaces than " " are kept."""
    return "".join(" " if unicodedata.category(ch) in ("Cc", "Zl", "Zp") else ch for ch in text)


def _local_prefs(path):
    """The Local server's settings, {} when the file or the subtree is missing or unreadable."""
    try:
        with open(path, "rb") as fh:
            prefs = plistlib.load(fh)
    except Exception:
        # Whatever plistlib raises for a damaged file (an XML one gives ExpatError): the generator
        # goes on with no settings then, so nothing of them is shown either.
        return {}
    servers = prefs.get("servers") if isinstance(prefs, dict) else None
    local = servers.get("local") if isinstance(servers, dict) else None
    return local if isinstance(local, dict) else {}


def _user_dir(prefs_path):
    return os.path.join(os.path.dirname(os.path.abspath(prefs_path)), sandbox_packs.USER_DIR_NAME)


def _text_list(value):
    return [item for item in value if isinstance(item, str) and item] if isinstance(value, list) else []


def _table_rows(own, session, granted):
    """Rows (path, From, kind) of one table: the user's own folders as stored, the session's
    temporary folder, then what only packs grant. A folder of the user's that a pack grants too
    is one row naming both; it stays the user's to remove."""
    rows = []
    listed = set()
    for path, kind, origin in [(path, "user", FROM_USER) for path in own] + \
                              [(path, "session", FROM_SESSION) for path in session]:
        if path in [row[0] for row in rows]:
            continue
        # Followed through links without opening the folder (os.path.realpath reads links only):
        # opening one macOS guards, such as Documents, could ask the user. A folder spelled in
        # another case than the disk's is then not matched, and shows as two rows.
        real = path
        if granted and path not in granted:
            try:
                real = os.path.realpath(path)
            except (OSError, ValueError):
                real = path
        listed.add(real)
        rows.append((path, ", ".join([origin] + granted.get(real, [])), kind))
    for path, titles in granted.items():
        if path not in listed:
            rows.append((path, ", ".join(titles), "pack"))
    return rows


def _write_rows(path, rows):
    with open(path, "w", encoding="utf-8") as fh:
        for row in rows:
            path_cell = _one_line(row[0]) if row[2] == "pack" else _stored_path(row[0])
            fh.write("\t".join((path_cell, _one_line(row[1]), row[2])) + "\n")


def pane(options):
    local = _local_prefs(options.prefs)
    ticked = sandbox_packs.ticked_ids(local.get(sandbox_packs.PREFS_KEY))
    read_only, read_write, files, summary = {}, {}, {}, []
    if ticked:
        project = local.get("project")
        packs = sandbox_packs.all_packs(options.bundle, _user_dir(options.prefs),
                                        project.strip() if isinstance(project, str) else "")
        read_only, read_write, files, _ = sandbox_packs.sourced_grants(ticked, packs)
        by_id = {pack.id: pack for pack in packs}
        for pack_id in ticked:
            pack = by_id.get(pack_id)
            if pack is None:
                summary.append(f"{pack_id} (missing)")
            elif pack.state == "ok":
                summary.append(pack.title)
            else:
                summary.append(f"{pack.title} ({_state_word(pack.state)})")
    for path, titles in files.items():
        read_only.setdefault(path, []).extend(titles)
    session = [options.session_tmpdir] if options.session_tmpdir else []
    _write_rows(options.out + ".rw.tsv", _table_rows(_text_list(local.get("allowed-write")), session, read_write))
    _write_rows(options.out + ".ro.tsv", _table_rows(_text_list(local.get("allowed-read")), [], read_only))
    with open(options.out + ".summary", "w", encoding="utf-8") as fh:
        fh.write(_one_line(", ".join(summary)) + "\n")
    return 0


def _state_word(state):
    return "not installed" if state == "not-installed" else "cannot be used"


def open_sheet(options):
    local = _local_prefs(options.prefs)
    project = local.get("project")
    packs = sandbox_packs.all_packs(options.bundle, _user_dir(options.prefs),
                                    project.strip() if isinstance(project, str) else "")
    with open(options.list, "w", encoding="utf-8") as fh:
        json.dump([pack.as_json() for pack in packs], fh)
    _write_ticked(options.ticked, sandbox_packs.ticked_ids(local.get(sandbox_packs.PREFS_KEY)))
    return 0


def _read_list(path):
    with open(path, "rb") as fh:
        packs = json.load(fh)
    return packs if isinstance(packs, list) else []


def _read_ticked(path):
    # `open` always writes the file, so one that is gone is an error like a missing list: read
    # as "nothing ticked", Use These Packs would store no packs over the ones chosen.
    with open(path, encoding="utf-8") as fh:
        return sandbox_packs.ticked_ids([line.strip() for line in fh if line.strip()])


def _write_ticked(path, ticked):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("".join(pack_id + "\n" for pack_id in ticked if "\n" not in pack_id))


def _shown_id(pack_id):
    """A pack's id as the table's hidden column and the handlers carry it. An invalid pack's id
    is its file's name, which can hold a tab or a line end: unchanged, it would add cells and
    rows to the table, and the checkboxes would then tick other packs than their rows show."""
    return _one_line(pack_id)


def rows(options):
    ticked = _read_ticked(options.ticked)
    for pack in _read_list(options.list):
        title = pack["title"]
        if pack["id"] in ticked:
            image = TICKED_IMAGE
        elif pack["state"] == "ok":
            image = UNTICKED_IMAGE
        else:
            image = UNUSABLE_IMAGE
        if pack["state"] != "ok":
            title += f" ({_state_word(pack['state'])})"
        print("\t".join((image, _one_line(title), _shown_id(pack["id"]))))
    return 0


def toggle(options):
    packs = _read_list(options.list)
    if not 0 <= options.row < len(packs):
        return 0
    pack = packs[options.row]
    ticked = _read_ticked(options.ticked)
    if pack["id"] in ticked:
        ticked.remove(pack["id"])
    elif pack["state"] == "ok":
        ticked.append(pack["id"])
    _write_ticked(options.ticked, ticked)
    print(_shown_id(pack["id"]))
    return 0


def _md_text(text):
    """Text of a pack shown as plain words: a pack file is somebody's, and its title or notes
    are not to be read as Markdown (a heading, a link, an image)."""
    return "".join("\\" + ch if ch in "\\`*_[]()<>#|!~" else ch for ch in _one_line(text))


def _md_code(text):
    return "`" + _one_line(text).replace("`", "'") + "`"


def _md_paths(heading, paths):
    if not paths:
        return []
    return ["", f"**{heading}**", ""] + ["- " + _md_code(path) for path in paths]


def preview(options):
    pack = next((pack for pack in _read_list(options.list) if _shown_id(pack["id"]) == options.id), None)
    if pack is None:
        return 0
    lines = ["## " + _md_text(pack["title"])]
    if pack["description"]:
        lines += ["", _md_text(pack["description"])]
    if pack["state"] == "not-installed":
        lines += ["", "**Not installed on this Mac:** " + _md_text(pack["reason"]) + ". The pack cannot be chosen."]
    elif pack["state"] != "ok":
        lines += ["", "**This pack cannot be used:** " + _md_text(pack["reason"]) + "."]
    else:
        lines += _md_paths("Folders to read and change", pack["read_write"])
        lines += _md_paths("Folders to read", pack["read_only"])
        lines += _md_paths("Single files to read", pack["read_only_files"])
        if not (pack["read_write"] or pack["read_only"] or pack["read_only_files"]):
            lines += ["", "Nothing this pack names is on this Mac, so it grants nothing here."]
        if pack["dropped"]:
            lines += ["", "**Left out on this Mac**", ""]
            lines += [f"- {_md_code(item['path'])} ({_md_text(item['reason'])})" for item in pack["dropped"]]
    if pack["notes"]:
        lines += ["", "**Notes**", ""] + ["- " + _md_text(note) for note in pack["notes"]]
    if pack["source"] == "user":
        lines += ["", "Your own pack, from " + _md_code(pack["path"]) + "."]
    print("\n".join(lines))
    return 0


def chosen(options):
    known = [pack["id"] for pack in _read_list(options.list)]
    for pack_id in _read_ticked(options.ticked):
        if pack_id in known and sandbox_packs.is_pack_id(pack_id):
            print(pack_id)
    return 0


def main(argv):
    parser = argparse.ArgumentParser(prog="sandbox_packs_view.py", allow_abbrev=False)
    commands = parser.add_subparsers(dest="command", required=True)
    takes = {
        "pane": (pane, ("--prefs", "--bundle", "--out")),
        "open": (open_sheet, ("--prefs", "--bundle", "--list", "--ticked")),
        "rows": (rows, ("--list", "--ticked")),
        "toggle": (toggle, ("--list", "--ticked")),
        "preview": (preview, ("--list", "--id")),
        "chosen": (chosen, ("--list", "--ticked")),
    }
    for name, (_, required) in takes.items():
        sub = commands.add_parser(name, allow_abbrev=False)
        for option in required:
            sub.add_argument(option, required=True)
        if name == "pane":
            sub.add_argument("--session-tmpdir", default="")
        if name == "toggle":
            sub.add_argument("--row", type=int, required=True)
    options = parser.parse_args(argv)
    try:
        return takes[options.command][0](options)
    except (OSError, ValueError, KeyError, TypeError) as e:
        # A list file that is gone or is not the one `open` wrote: the sheet's handler says so.
        print(f"sandbox_packs_view: {options.command}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
