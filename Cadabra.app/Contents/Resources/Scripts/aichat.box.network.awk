# aichat.box.network.awk - the connection rows and allow rules of aichat.box.network.library.sh.
#
#     printf '%s\t%s\t%s\n' host port method | /usr/bin/awk -F'\t' -v mode=rule -f aichat.box.network.awk
#     agentvm_netlog rows | /usr/bin/awk -F'\t' -v mode=rows -v since=TIME -f aichat.box.network.awk
#
# Modes:
#   rule  one line in (host, port, method), the allow rule for it out, or "-" (see rule() below).
#   rows  agentvm_netlog's rows in (time, decision, host, port, method, reason), one row out per
#         host, port and outcome since TIME, unsorted and led by two sort keys: the rank (refused
#         1, failed 2, reached 3) and the last time, then host, port, the outcome's mark,
#         connections, why, rule, decision. The library sorts and drops the keys.

# rule(host, port, method) is the allow rule for one connection, or "-" when the host is not a
# plain host name. A plain host covers port 443 for a tunnel (CONNECT) and 80 for plain HTTP, as
# agent-vm reads it; any other port is named ("host:8443"). Host names are letters, digits, "."
# and "-", starting with a letter or digit and holding at least one letter: an IP address is
# refused (agent-vm's rules name hosts), and so is "public", agent-vm's rule for any public host.
# The letters are spelled out because a bracket range follows the locale's collation order.
# Trailing dots go, as agent-vm drops them when it matches a host, and every label must be 1 to 63
# characters, or agent-vm refuses the rule. A raw tunnel to port 80 gets no rule: agent-vm leaves
# it out of a plain host's ports on purpose, since a raw request there can name another site the
# server hosts. _n, _i and _label are locals. Whatever passes, agent-vm still refuses a host that
# resolves to an address on this Mac or the local network.
function rule(host, port, method,    _n, _i, _label) {
    host = tolower(host)
    sub(/\.+$/, "", host)
    if (host !~ /^[abcdefghijklmnopqrstuvwxyz0123456789][abcdefghijklmnopqrstuvwxyz0123456789.-]*$/ \
        || host !~ /[abcdefghijklmnopqrstuvwxyz]/ || host == "public" || length(host) > 253 \
        || port !~ /^[0123456789]+$/ || port + 0 < 1 || port + 0 > 65535) return "-"
    _n = split(host, _label, ".")
    for (_i = 1; _i <= _n; _i++) if (_label[_i] == "" || length(_label[_i]) > 63) return "-"
    if (method == "CONNECT" && port + 0 == 80) return "-"
    if ((method == "CONNECT" && port + 0 == 443) || (method != "CONNECT" && port + 0 == 80)) return host
    return host ":" (port + 0)
}

mode == "rule" { print rule($1, $2, $3); next }

mode == "rows" && (NF < 6 || $1 < since) { next }

mode == "rows" {
    key = $3 SUBSEP $4 SUBSEP $2
    if (!(key in count)) { order[++n] = key; host[key] = $3; port[key] = $4; decision[key] = $2 }
    count[key]++
    last[key] = $1
    method[key] = $5
    why[key] = $6
}

# The outcome's mark, one for each decision agent-vm logs: a stop sign for refused (denied), a
# warning sign for failed (allowed, but resolving or connecting failed), a check mark for reached
# (allowed). The Why column says the reason or the rule.
END {
    if (mode != "rows") exit
    for (i = 1; i <= n; i++) {
        k = order[i]
        rank = decision[k] == "denied" ? 1 : (decision[k] == "failed" ? 2 : 3)
        mark = decision[k] == "denied" ? "🛑" : (decision[k] == "failed" ? "⚠️" : "✅")
        printf "%d\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%s\n", rank, last[k], host[k], port[k], mark, count[k], why[k],
            rule(host[k], port[k], method[k]), decision[k]
    }
}
