# aichat.allow.folder.refused.awk - the path a tool call's result says it was refused, for
# allow_folder_refused_path in aichat.allow.folder.library.sh.
#
#     <the result's text> | /usr/bin/awk -f aichat.allow.folder.refused.awk
#
# One line out, the path as the tool wrote it, or nothing. A server's own refusal is looked for
# first, on any line:
#   the Local server   "Path not allowed: PATH is outside the allowed directories"
#   the PDF server     "... outside allowed roots: PATH"   (PATH ends at a quote or the line's end)
# and then the first line of a command's output of the form "tool: PATH: Operation not
# permitted" whose PATH is absolute. PATH is what follows the last ": /" before the error text,
# so a tool named by its own path ("/bin/sh: /x/y: Operation not permitted") gives /x/y.

found == "" {
    start = index($0, "Path not allowed: ")
    end = index($0, " is outside the allowed directories")
    if (start > 0 && end > start + 18) {
        found = substr($0, start + 18, end - start - 18)
    }
}
found == "" {
    start = index($0, "outside allowed roots: ")
    if (start > 0) {
        found = substr($0, start + 23)
        sub(/".*$/, "", found)
    }
}
command == "" {
    end = index($0, ": Operation not permitted")
    if (end > 1) {
        line = substr($0, 1, end - 1)
        while ((at = index(line, ": /")) > 0) {
            line = substr(line, at + 2)
        }
        if (substr(line, 1, 1) == "/") {
            command = line
        }
    }
}
END {
    if (found != "") { print found } else if (command != "") { print command }
}
