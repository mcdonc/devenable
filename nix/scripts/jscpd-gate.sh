#!/usr/bin/env bash
# Token-clone gate. Ported from mcdonc/msks scripts/jscpd-gate.sh (MIT).
#
# jscpd exits 1 when it finds any exact clone of at least 70 tokens in
# the graded sources. This script owns the gate invocation so the
# threshold and the scanned file set have exactly one definition.
#
# The scanned set is the graded sources, tracked OR untracked-but-
# present (--cached --others --exclude-standard, the same scoping
# xenon-gate.sh uses, so the gates grade the same files): gitignored
# scratch stays out, while a new file that is present grades
# immediately. A deliberate in-tree clone gets recorded in a tracking
# issue and committed with ``git commit --no-verify`` — the escape
# hatch is recording, never suppression flags.
#
# Usage: jscpd-gate.sh [jscpd flags...]
#   Extra flags append to the fixed gate invocation.
set -euo pipefail

# The scanned sources, as git pathspecs (* matches across
# directories). The configuring agent points these at this
# project's Python package.
GATE_GLOBS=('sample/src/*.py')

cd "$(dirname "$0")/../.."

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(git ls-files --cached --others --exclude-standard "${GATE_GLOBS[@]}")
if [ "${#files[@]}" -eq 0 ]; then
  echo "jscpd-gate: no graded .py files found — run from the repo root, and check GATE_GLOBS in nix/scripts/jscpd-gate.sh" >&2
  exit 1
fi

exec jscpd "${files[@]}" --min-tokens 70 --exit-code --no-tips "$@"
