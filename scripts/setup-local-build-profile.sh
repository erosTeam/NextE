#!/usr/bin/env bash
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
cd "$repo"

git config core.hooksPath .githooks

if [ ! -f build-profile.local.json5 ]; then
  cp build-profile.json5 build-profile.local.json5
  chmod 600 build-profile.local.json5 || true
  echo 'Created build-profile.local.json5 from current build-profile.json5. Edit it for local signing if needed.'
fi

git update-index --no-skip-worktree build-profile.json5 2>/dev/null || true
git checkout -- build-profile.json5
git update-index --skip-worktree build-profile.json5
cp build-profile.local.json5 build-profile.json5
chmod 600 build-profile.local.json5 || true

echo 'Local build-profile.json5 is installed from build-profile.local.json5.'
echo 'Git index keeps the public build-profile.json5.'
echo 'Hooks are enabled via core.hooksPath=.githooks.'
