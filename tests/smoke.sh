#!/usr/bin/env bash
# Copy the template into a scratch project and verify it activates.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/project"
git init -q "$tmp/project"
cp -r "$root/nix" "$tmp/project/nix"
cp -r "$root/sample" "$tmp/project/sample"

cd "$tmp/project"
devenv --from path:./nix allow
devenv --quiet shell -- hello
devenv --quiet shell -- python -c 'import samplepy; assert samplepy.greet("x")'

test -f devenv.lock   # lock lands at the project root
test -d .devenv       # state lands at the project root
test ! -e nix/.devenv # nothing generated inside the template dir
test ! -e nix/devenv.lock
test -f .git/hooks/pre-commit # git hooks installed at commit-time location

echo "smoke ok"
