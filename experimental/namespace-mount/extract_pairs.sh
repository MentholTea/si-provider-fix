#!/system/bin/sh
# Emit "source<TAB>target" pairs from Storage Isolation's configuration.
#
# Device has no jq/python3, so this is a small tokenizer over the raw JSON:
#   - isolate the "observers" array
#   - split it into {...} objects (string state respected, escapes handled)
#   - pull package_name / source / target / enabled out of each object
#   - print "<source>\t<target>" for every enabled rule with both paths present
#
# Usage: extract_pairs.sh <configuration.json>

CONFIG="$1"

[ -f "$CONFIG" ] || exit 1

awk '
function field(obj, key,    pat, n, seg) {
    pat = "\"" key "\"[ \t]*:[ \t]*\""
    if (!match(obj, pat)) return ""
    seg = substr(obj, RSTART + RLENGTH)
    n = index(seg, "\"")
    if (n <= 0) return ""
    return substr(seg, 1, n - 1)
}
function boolfield(obj, key,    pat, seg) {
    pat = "\"" key "\"[ \t]*:[ \t]*"
    if (!match(obj, pat)) return "true"
    seg = substr(obj, RSTART + RLENGTH)
    if (substr(seg, 1, 5) == "false") return "false"
    return "true"
}
# strip a leading /storage/emulated/<n>/ or /, and trailing slashes
function clean(p,    i, j, s) {
    s = p
    i = index(s, "storage/emulated/")
    if (i > 0) {
        j = index(substr(s, i + 17), "/")
        if (j > 0) s = substr(s, i + 17 + j)
    }
    while (substr(s, 1, 1) == "/") s = substr(s, 2)
    while (substr(s, length(s), 1) == "/") s = substr(s, 1, length(s) - 1)
    return s
}

{ raw = raw $0 "\n" }

END {
    if (!match(raw, /"observers"[ \t]*:[ \t]*\[/)) exit 0
    body = substr(raw, RSTART + RLENGTH)
    len = length(body)
    depth = 1
    cur = ""
    nobj = 0
    instr = 0

    for (i = 1; i <= len; i++) {
        c = substr(body, i, 1)
        if (instr) {
            cur = cur c
            if (c == "\\") { i++; cur = cur substr(body, i, 1); continue }
            if (c == "\"") instr = 0
            continue
        }
        if (c == "\"") { instr = 1; cur = cur c; continue }
        if (c == "{") { depth++; if (depth == 2) { cur = "{"; continue } }
        if (c == "}") {
            depth--
            if (depth == 1) { cur = cur "}"; obj[++nobj] = cur; cur = ""; continue }
        }
        if (c == "]" && depth == 1) break
        if (depth >= 2) cur = cur c
    }

    for (k = 1; k <= nobj; k++) {
        o = obj[k]
        if (boolfield(o, "enabled") == "false") continue
        src = clean(field(o, "source"))
        tgt = clean(field(o, "target"))
        if (src == "" || tgt == "") continue
        printf "%s\t%s\n", src, tgt
    }
}
' "$CONFIG"
