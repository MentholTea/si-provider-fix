#!/system/bin/sh
# Extract Storage Isolation export rules (observers[]) into the module's compact schema.
#
# Device has no jq/python3, so this is a small tokenizer over the raw JSON:
#   - isolate the "observers" array
#   - split it into "{...}" objects (strings are respected, escaped quotes included)
#   - pull package_name / source / target / enabled / user_id out of each object
#   - emit {"version":1,"rules":[...]} with JSON-escaped values
#
# Usage: extract_rules.sh <configuration.json> <output.json>

CONFIG="$1"
OUT="$2"

[ -f "$CONFIG" ] || { echo "missing config" >&2; exit 1; }
[ -n "$OUT" ] || { echo "missing output" >&2; exit 1; }

awk '
function jesc(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    gsub(/\t/, " ", s)
    gsub(/\n/, " ", s)
    gsub(/\r/, "", s)
    return s
}
function field(obj, key,    pat, n, i, seg, val) {
    pat = "\"" key "\"[ \t]*:[ \t]*\""
    if (!match(obj, pat)) {
        return ""
    }
    seg = substr(obj, RSTART + RLENGTH)
    n = index(seg, "\"")
    if (n <= 0) {
        return ""
    }
    return substr(seg, 1, n - 1)
}
function boolfield(obj, key,    pat, seg) {
    pat = "\"" key "\"[ \t]*:[ \t]*"
    if (!match(obj, pat)) {
        return "true"
    }
    seg = substr(obj, RSTART + RLENGTH)
    if (substr(seg, 1, 5) == "false") {
        return "false"
    }
    return "true"
}

{
    raw = raw $0 "\n"
}

END {
    # locate the observers array
    if (!match(raw, /"observers"[ \t]*:[ \t]*\[/)) {
        printf "{\"version\":1,\"rules\":[]}" > "'"$OUT"'"
        exit 0
    }
    body = substr(raw, RSTART + RLENGTH)
    depth = 1
    cur = ""
    nobj = 0

    # walk characters, tracking {} depth and string state
    len = length(body)
    instr = 0
    for (i = 1; i <= len; i++) {
        c = substr(body, i, 1)
        if (instr) {
            cur = cur c
            if (c == "\\") {
                i++
                cur = cur substr(body, i, 1)
                continue
            }
            if (c == "\"") {
                instr = 0
            }
            continue
        }
        if (c == "\"") {
            instr = 1
            cur = cur c
            continue
        }
        if (c == "{") {
            depth++
            if (depth == 2) {
                cur = "{"
                continue
            }
        }
        if (c == "}") {
            depth--
            if (depth == 1) {
                cur = cur "}"
                obj[++nobj] = cur
                cur = ""
                continue
            }
        }
        if (c == "]" && depth == 1) {
            break
        }
        if (depth >= 2) {
            cur = cur c
        }
    }

    printf "{\"version\":1,\"rules\":[" > "'"$OUT"'"
    first = 1
    for (k = 1; k <= nobj; k++) {
        o = obj[k]
        if (boolfield(o, "enabled") == "false") {
            continue
        }
        pkg = field(o, "package_name")
        src = field(o, "source")
        tgt = field(o, "target")
        if (pkg == "" || src == "" || tgt == "") {
            continue
        }
        if (!first) {
            printf "," >> "'"$OUT"'"
        }
        first = 0
        printf "{\"pkg\":\"%s\",\"source\":\"%s\",\"target\":\"%s\"}", jesc(pkg), jesc(src), jesc(tgt) >> "'"$OUT"'"
    }
    printf "]}" >> "'"$OUT"'"
}
' "$CONFIG"

[ -s "$OUT" ] || { echo "empty output" >&2; exit 1; }
exit 0
