#!/usr/bin/env bash
# Module-length gate: no module past the ceiling. Ported from
# mcdonc/msks scripts/lines-gate.sh (MIT).
#
# The gate does one thing — it fails, naming the file and its line
# count. It never edits, splits, or suggests.
#
# The exemption list is nix/scripts/lines-exemptions.txt (seeded
# empty): one path per line, everything after the path is the reason.
# The list only shrinks — an entry whose file is at or under the
# ceiling fails the gate as stale, and the commit that brings a listed
# file back under removes its entry.
#
# Usage: lines-gate.sh [ROOT] [--exemptions FILE]
#   ROOT defaults to this script's repo root. The exemption file
#   defaults to ROOT/nix/scripts/lines-exemptions.txt; a missing
#   file reads as the empty list. bash 3.2 compatible — no mapfile,
#   no associative arrays, macOS hosts included.
#
# Paths parse at the first whitespace, so a path containing a
# space never matches an entry and fails as an offender — the
# gate stays loud, never silently permissive.
set -euo pipefail

# The ceiling, in lines. It only goes down. Counting is
# ``grep -c ''`` — wc -l undercounts a file whose final line
# lacks its newline, and the unterminated variant of an
# over-ceiling file would slip past.
MAX_LINES=1000

# The scanned sources, as a git pathspec (* matches across
# directories). The configuring agent points this at this
# project's Python package.
GATE_GLOB='sample/src/*.py'

root=$(cd "$(dirname "$0")/../.." && pwd)
exemptions=""
positional=()
while [ "$#" -gt 0 ]; do
  case "$1" in
  --exemptions)
    exemptions=$2
    shift 2
    ;;
  *)
    positional+=("$1")
    shift
    ;;
  esac
done
if [ "${#positional[@]}" -gt 1 ]; then
  echo "usage: lines-gate.sh [ROOT] [--exemptions FILE]" >&2
  exit 1
fi
if [ "${#positional[@]}" -gt 0 ]; then
  root=$(cd "${positional[0]}" && pwd)
fi
if [ -z "$exemptions" ]; then
  exemptions="$root/nix/scripts/lines-exemptions.txt"
fi

# Scanned set: the graded sources, tracked OR untracked-but-present
# (--cached --others --exclude-standard), the same scoping
# xenon-gate.sh and jscpd-gate.sh use, so all gates grade the same
# files. gitignored scratch stays out; a new file grades at once
# instead of escaping until the commit hook catches it.
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(git -C "$root" ls-files --cached --others --exclude-standard "$GATE_GLOB")
if [ "${#files[@]}" -eq 0 ]; then
  echo "lines-gate: no .py files found for '$GATE_GLOB' — is $root the repo root, and is GATE_GLOB in nix/scripts/lines-gate.sh set for this project?" >&2
  exit 1
fi

# Exemption entries: one path per line, reason after the path.
# Blank lines and comments skip (leading whitespace allowed);
# every other line grades as a path — a bogus one fails the
# stale pass loudly instead of being swallowed.
exempted=()
if [ -f "$exemptions" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    trim=${line#"${line%%[![:space:]]*}"}
    case "$trim" in
    '' | \#*) continue ;;
    esac
    read -r path _reason <<<"$trim"
    [ -n "$path" ] || continue
    exempted+=("$path")
  done <"$exemptions"
fi

# Every over-ceiling file, "count path" per line — the count
# carries no space, so ${entry#* } keeps the path whole, spaces
# included. An exemption entry is valid only while its path
# appears here: an entry for a file at or under the ceiling, or
# absent from the tree, is stale.
over=""
for f in "${files[@]}"; do
  n=$(grep -c '' "$root/$f" || true)
  if [ "$n" -gt "$MAX_LINES" ]; then
    over+="$n $f"$'\n'
  fi
done

# Exact membership of $1 among the over-ceiling paths — full
# paths on both sides, so an entry and an offender can never
# disagree about what a line names.
is_over() {
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if [ "${entry#* }" = "$1" ]; then
      return 0
    fi
  done <<<"$over"
  return 1
}

fail=0

# Offender pass: every over-ceiling path the list does not
# carry, reported with its full path and count.
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  count=${entry%% *}
  path=${entry#* }
  exempt=0
  for e in ${exempted[@]+"${exempted[@]}"}; do
    if [ "$e" = "$path" ]; then
      exempt=1
      break
    fi
  done
  if [ "$exempt" -eq 0 ]; then
    echo "lines-gate: FAIL — $path is $count lines (ceiling $MAX_LINES); split it into a package (the exemption list is the last resort)" >&2
    fail=1
  fi
done <<<"$over"

# Stale pass: every listed path must name a real over-ceiling file.
for e in ${exempted[@]+"${exempted[@]}"}; do
  if ! is_over "$e"; then
    echo "lines-gate: FAIL — stale exemption: $e is at or under the ceiling (or absent); remove the entry in the commit that split it" >&2
    fail=1
  fi
done

exit "$fail"
