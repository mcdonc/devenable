"""Greeting helpers."""

import json


def greet(name: str) -> str:  # rank A: one branch, trivial cyclomatic load
    """Return a JSON greeting for *name* (empty names are refused)."""
    if not name:
        raise ValueError("name must not be empty")
    return json.dumps({"greeting": f"Hello, {name}!"})
