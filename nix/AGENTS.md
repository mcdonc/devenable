# nix/ — this project's development environment

This directory is this project's devenv configuration, copied from the
`devenable` template and then configured for this project. The project root
is bound to it as an out-of-tree `path:` source, so no devenv files live in
the project root except `devenv.lock` (committed). Generated state (`.devenv/`)
also lands at the root and must stay untracked.

## Fresh clone (per machine)

```bash
cd <project root>
devenv --from path:./nix allow   # binds this directory to the config
printf '%s\n' '.devenv/' '.pre-commit-config.yaml' '.prettierignore' >> .git/info/exclude
```

After `allow`, plain `devenv shell` works from anywhere in the project.

## Setup (configuring agent — once, after copying this directory in)

1. Inspect the project and rewrite `devenv.nix` for its stack: languages,
   `packages`, `env`, `enterShell`, `processes`/`tasks` as needed. Remove
   unused sections and the example `hello` script.
   For Python projects: point `GATE_GLOBS`/`GATE_GLOB` at the top of each
   gate script in `nix/scripts/` (xenon, jscpd, lines-gate) and
   `PKG_ROOT`/`PACKAGE` in `check_import_cycles.py` at the project's
   package — the template ships them pointed at its own sample project
   (`sample/src`). For non-Python projects, delete the Python-only hooks
   (ruff-*, xenon, lines-gate, jscpd, deferred-imports, import-cycles)
   and their gate scripts.
2. Bind and verify:

   ```bash
   cd <project root>
   devenv --from path:./nix allow
   devenv --quiet shell -- true
   ```

3. `devenv.lock` appears at the project root — commit it. It pins the
   inputs from `devenv.yaml` for everyone. Do not create any other devenv
   files or directories in the project root.
4. Keep root state untracked without adding root files:
   `printf '%s\n' '.devenv/' '.pre-commit-config.yaml' '.prettierignore' >> .git/info/exclude`
   (or append them to an existing `.gitignore`).
5. Make the environment discoverable for agents and humans who do NOT
   have a global devenv convention (most users). Agents do not reliably
   read nested AGENTS.md files, so the conventions must be surfaced from
   the project root:
   - Append the block below to the project's root `AGENTS.md` (create
     the file if the project has none):

     ```markdown
     ## Development environment

     This project uses devenv with an out-of-tree config in `nix/`
     (full conventions in `nix/AGENTS.md`). Run commands from the
     project root:

         devenv --quiet shell -- <command>

     Never pass `-O` option overrides: under the out-of-tree binding
     they make devenv silently drop the profile from the shell.
     dotenv is already disabled in `nix/devenv.nix`.
     Fresh clone: `devenv --from path:./nix allow`.
     ```

   - Add a short "Development environment" section to the project
     README for humans: the `devenv allow` fresh-clone step, and
     `devenv shell` to enter the environment.
6. Commit `nix/` (including this file) together with the root
   `AGENTS.md`/README changes.

## Conventions (all agents)

- Run every project command from the project root:

  ```bash
  devenv --quiet shell -- <command>
  ```

  Do NOT add `-O ...` overrides: with the out-of-tree binding, devenv
  (≤ 2.3.1) silently drops the profile from PATH. dotenv is already
  disabled in `devenv.nix`.

- Add tools by editing `packages` in `devenv.nix`, never by installing
  packages globally.
- Paths: commands run with cwd = project root; Nix path literals inside
  `devenv.nix` resolve relative to that file (`./x` = template-owned,
  `../x` = source tree); `$DEVENV_ROOT` is the project root.
- Template-owned scripts live in `nix/scripts/` and are wired through
  `scripts.<name>.exec` in `devenv.nix`.
- Update inputs with `devenv update` from the project root, then commit the
  regenerated `devenv.lock`.
- Personal, uncommitted tweaks go in `devenv.local.nix` (gitignored).
- Git hooks default to the `msks` set: ruff, shfmt, shellcheck, shebang
  guard, markdownlint, actionlint, trufflehog, nixfmt, check-toml,
  yamllint, prettier, plus the script-based gates (xenon, lines-gate,
  jscpd, deferred-imports, import-cycles) in `nix/scripts/`. They run
  at `git commit` time — a failing hook does not block `devenv shell`.
  A deliberate offender is committed with `git commit --no-verify` and a
  recorded reason — the escape hatch is recording, never suppression
  flags. Add project-specific gates under `git-hooks.hooks` in
  `devenv.nix` if the project needs them.
