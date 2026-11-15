#!/usr/bin/env python3
"""Import-cycle gate.

Ported from mcdonc/msks scripts/check_import_cycles.py (MIT).

Walks every import under PKG_ROOT with ``ast`` — module level,
deferred, typing-only alike; for a layering contract every import the
tree carries is an edge — and fails when the module import graph has a
cycle: Python must resolve the loop by partial initialization.

The walk counts an import as a module edge only when it can loop: a
module importing itself or its own ancestor package is the standard
intra-package idiom (the ancestor is already initialized or
initializing when the module runs) and never contributes.

Runs at commit time (the generated pre-commit hook); exit status 1
names the cycle's chain with the file:line of each import along it.

A star import creates only the edge on the module itself; the names it
spreads create none (ruff's F403 rejects star imports before this gate
ever runs). Everything else the ``ast`` walker sees, this gate sees.
"""

import ast
import itertools
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
# The package tree to grade, and the top-level package name its modules
# import under. The configuring agent points these at this project's
# Python package. For a src layout (package at src/mypkg imported as
# `mypkg`) set: PKG_ROOT = REPO_ROOT / "src" / "mypkg"; PACKAGE = "mypkg".
# A wrong pairing fails VACUOUSLY (no edge resolves inside PACKAGE and
# the gate passes with no modules graded) — set both, then run the
# script by hand once and check it names your package in its pass line.
PKG_ROOT = REPO_ROOT / "sample" / "src" / "samplepy"
PACKAGE = "samplepy"


def module_of(path: Path) -> tuple[str, ...] | None:
    """The dotted module path for a file under PKG_ROOT, or None
    for a file outside the package's __init__.py chains (trees the
    app loads by exec, outside the import system)."""
    top = None
    cur = path.parent
    while (cur / "__init__.py").is_file():
        top = cur
        if cur.parent == cur:
            break
        cur = cur.parent
    if top is None:
        return None
    stem = path.relative_to(top).with_suffix("").parts
    if stem[-1] == "__init__":
        stem = stem[:-1]
    return (top.name, *stem)


def relative_base(
    pkg_parts: tuple[str, ...], node: ast.ImportFrom
) -> tuple[str, ...] | None:
    """The package prefix a relative ImportFrom resolves against,
    or None when it climbs past the package root."""
    if node.level > len(pkg_parts):
        return None
    if node.level:
        return pkg_parts[: len(pkg_parts) - (node.level - 1)]
    return ()


def resolved_module(node: ast.ImportFrom, base: tuple[str, ...]) -> tuple[str, ...]:
    """``base`` plus the statement's dotted module, when it has
    one."""
    return base + (tuple(node.module.split(".")) if node.module else ())


def public_names(node: ast.ImportFrom) -> list[str]:
    """The imported names, star imports excluded."""
    return [a.name for a in node.names if a.name != "*"]


def from_targets(node: ast.ImportFrom, base: tuple[str, ...]) -> list[tuple[str, ...]]:
    """Dotted targets of ``from <module> import names`` resolved
    under ``base``.

    The module itself is always a target — the statement executes
    it — so cycles through it close. Each imported name appends a
    leaf beneath it: a name that is a submodule imports it, and any
    other is a phantom that can never be a cycle's source."""
    mod = resolved_module(node, base)
    if not mod:
        return [(n,) for n in public_names(node)]
    return [mod, *(mod + (n,) for n in public_names(node))]


def import_targets(pkg_parts: tuple[str, ...], node: ast.AST) -> list[tuple[str, ...]]:
    """Dotted absolute targets of one import statement."""
    if isinstance(node, ast.Import):
        return [tuple(a.name.split(".")) for a in node.names]
    if not isinstance(node, ast.ImportFrom):
        return []
    base = relative_base(pkg_parts, node)
    return from_targets(node, base) if base is not None else []


def statement_imports(pkg_parts: tuple[str, ...], node: ast.AST):
    """Yield ``(lineno, dst_module)`` for one statement's imports
    that resolve inside the graded package."""
    for target in import_targets(pkg_parts, node):
        if target and target[0] == PACKAGE:
            yield node.lineno, target


def file_imports(path: Path, parts: tuple[str, ...]):
    """Yield ``(lineno, dst_module)`` for one file's imports that
    resolve inside the graded package."""
    pkg_parts = parts if path.name == "__init__.py" else parts[:-1]
    tree = ast.parse(path.read_text(), filename=str(path))
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Import, ast.ImportFrom)):
            continue
        yield from statement_imports(pkg_parts, node)


def intra_package_imports():
    """Yield ``(file, lineno, src_module, dst_module)`` for every
    import under PKG_ROOT that resolves inside the graded package."""
    for path in sorted(PKG_ROOT.rglob("*.py")):
        if "__pycache__" in path.parts:
            continue
        parts = module_of(path)
        if parts is None:
            continue
        for lineno, target in file_imports(path, parts):
            yield path, lineno, parts, target


def import_sites() -> dict[tuple[str, str], tuple[str, int]]:
    """Module edges that can loop: ``{(src, dst): (file, line)}``."""
    sites: dict[tuple[str, str], tuple[str, int]] = {}
    for path, lineno, src, dst in intra_package_imports():
        src_name, dst_name = ".".join(src), ".".join(dst)
        if dst_name == src_name or src_name.startswith(dst_name + "."):
            continue
        site = (str(path.relative_to(PKG_ROOT)), lineno)
        sites.setdefault((src_name, dst_name), site)
    return sites


def find_cycle() -> list[str] | None:
    """One import cycle as a module chain (first repeats last), or
    None when the graph is acyclic."""
    sites = import_sites()
    WHITE, GREY, BLACK = 0, 1, 2
    color: dict[str, int] = {}
    stack: list[str] = []

    def visit(module: str) -> str | None:
        color[module] = GREY
        stack.append(module)
        for src, dst in sites:
            if src != module:
                continue
            state = color.get(dst, WHITE)
            if state == GREY:
                return dst  # a back-edge: the import stack loops
            if state == WHITE:
                found = visit(dst)
                if found:
                    return found
        color[module] = BLACK
        stack.pop()
        return None

    for module in dict.fromkeys(src for src, _ in sites):
        if color.get(module, WHITE) == WHITE:
            found = visit(module)
            if found:
                return stack[stack.index(found) :] + [found]
    return None


def main() -> int:
    cycle = find_cycle()
    if cycle is None:
        print(f"check_import_cycles: none under {PKG_ROOT}")
        return 0
    sites = import_sites()
    chain = []
    for src, dst in itertools.pairwise(cycle):
        file, line = sites[(src, dst)]
        chain.append(f"{src} -> {dst} ({file}:{line})")
    print(
        "check_import_cycles: import cycle:\n  " + "\n  ".join(chain),
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
