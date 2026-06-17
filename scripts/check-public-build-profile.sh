#!/usr/bin/env bash
set -euo pipefail

mode="${1:---worktree}"
repo="$(git rev-parse --show-toplevel)"
cd "$repo"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

case "$mode" in
  --staged)
    git show ':build-profile.json5' > "$tmp" 2>/dev/null || exit 0
    src="staged build-profile.json5"
    ;;
  --head)
    git show 'HEAD:build-profile.json5' > "$tmp" 2>/dev/null || exit 0
    src="HEAD:build-profile.json5"
    ;;
  --worktree)
    [ -f build-profile.json5 ] || exit 0
    cp build-profile.json5 "$tmp"
    src="worktree build-profile.json5"
    ;;
  *)
    echo "usage: $0 [--staged|--head|--worktree]" >&2
    exit 2
    ;;
esac

python3 - "$src" "$tmp" <<'PY'
import re, sys
src, path = sys.argv[1], sys.argv[2]
text = open(path, encoding='utf-8', errors='ignore').read()
patterns = [
    ('non-empty password field', re.compile(r'(?i)"(?:storePassword|keyPassword|password|passwd)"\s*:\s*"[^"]+"')),
    ('local absolute path', re.compile(r'(?i)(/Users/|/home/|\\\\Users\\\\|~/|\$\{HOME\})')),
    ('private signing material file', re.compile(r'(?i)\.(?:p12|p7b)\b')),
    ('debug signing directory marker', re.compile(r'(?i)debug-signing')),
]
hits=[]
for i,line in enumerate(text.splitlines(), 1):
    for name,pat in patterns:
        if pat.search(line):
            hits.append((i,name))
if hits:
    print(f'BLOCKED: {src} looks local/secret-bearing.')
    for line,name in hits[:30]:
        print(f'  line {line}: {name}')
    if len(hits) > 30:
        print(f'  ... {len(hits)-30} more hit(s)')
    sys.exit(1)
PY
