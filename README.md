# devenable

A template `nix/` directory to copy into existing projects. Each project
gets its own copy, configures it for its stack, and binds the project root
to it as an out-of-tree devenv source.

## Use

```bash
cp -r ~/projects/devenable/nix /path/to/project/nix
```

Then either tell an agent: _"Read nix/AGENTS.md and set this project up"_,
or manually:

```bash
cd /path/to/project
devenv --from path:./nix allow
devenv --quiet shell -- true
printf '%s\n' '.devenv/' '.pre-commit-config.yaml' '.prettierignore' >> .git/info/exclude
git add devenv devenv.lock
```

## Design

- **Out-of-tree `path:` source.** The project root is bound to `./devenv`
  with `devenv allow` (devenv ≥ 2.2). Plain `devenv shell` then works from
  the root; the binding is stored per-user, not in the project.
- **Root stays clean.** The only devenv artifacts at the project root are
  `devenv.lock` (committed — it pins inputs) and `.devenv/` (untracked,
  excluded via `.git/info/exclude` so no root file is created).
- **No lock in the template.** The project root's lock is authoritative;
  a shipped lock inside `nix/` would be ignored.
- **Copies diverge.** `cp -r` is fire-and-forget: template updates do not
  propagate to projects already set up.
- **Self-contained conventions.** Users need no global agent conventions;
  setup writes a pointer block into the project's root `AGENTS.md` and a
  dev-environment section into its README (see `nix/AGENTS.md`).
- **msks gates.** Pre-commit defaults to the mcdonc/msks hook set,
  including the script-based gates (xenon, lines-gate, jscpd,
  deferred-imports, import-cycles) ported into `nix/scripts/`; the
  gate scripts' `GATE_GLOBS`/`PKG_ROOT` knobs get pointed at the
  project's package during setup.

## Test

```bash
tests/smoke.sh
```
