#!/usr/bin/env bash
# Example template-owned script. cwd is the project root when run from a
# devenv shell; DEVENV_ROOT is the project root.
set -euo pipefail
echo "hello from devenv/scripts/$(basename "$0")"
echo "DEVENV_ROOT=$DEVENV_ROOT"
echo "cwd=$PWD"
