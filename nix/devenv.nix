# Development environment for this project.
#
# Path conventions (see AGENTS.md next to this file):
#   - Commands run with cwd = project root, so relative paths in commands,
#     processes, and scripts point at the source tree.
#   - Nix path literals resolve relative to this file:
#       ./x  -> nix/x   (template-owned)
#       ../x -> <project root>/x   (source tree)
#   - $DEVENV_ROOT is the project root.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  # jscpd token-clone scanner (pinned per-platform binary, the msks
  # pattern): 5.x ships a prebuilt Rust binary via platform-specific
  # npm packages (esbuild-style), so it is not in nixpkgs; pin the
  # binary per platform with fixed hashes. One pinned version keeps
  # clone reports reproducible across contributors and CI. Any other
  # platform fails at eval time instead of silently installing a
  # foreign-arch binary.
  jscpdBinaryVersion = "5.0.16";
  jscpd = pkgs.stdenv.mkDerivation {
    pname = "jscpd";
    version = jscpdBinaryVersion;
    src = pkgs.fetchurl {
      url =
        if pkgs.stdenv.isDarwin then
          "https://registry.npmjs.org/jscpd-darwin-"
          + (if pkgs.stdenv.hostPlatform.darwinArch == "arm64" then "arm64" else "x64")
          + "/-/jscpd-darwin-"
          + (if pkgs.stdenv.hostPlatform.darwinArch == "arm64" then "arm64" else "x64")
          + "-${jscpdBinaryVersion}.tgz"
        else if pkgs.stdenv.hostPlatform.isx86_64 then
          "https://registry.npmjs.org/jscpd-linux-x64-gnu/-/jscpd-linux-x64-gnu-${jscpdBinaryVersion}.tgz"
        else if pkgs.stdenv.hostPlatform.isAarch64 then
          "https://registry.npmjs.org/jscpd-linux-arm64-gnu/-/jscpd-linux-arm64-gnu-${jscpdBinaryVersion}.tgz"
        else
          throw "jscpd: no prebuilt binary for ${pkgs.stdenv.hostPlatform.system}";
      hash =
        if pkgs.stdenv.isDarwin then
          (
            if pkgs.stdenv.hostPlatform.darwinArch == "arm64" then
              "sha256-vntXwMkns8HqtHwVzxthzun0tpRAe755YKB5k4c3Wqg="
            else
              "sha256-X2hK+EAgrXGRLUymdo5qgTuWoFQ3U0cz9J064UFQppM="
          )
        else if pkgs.stdenv.hostPlatform.isx86_64 then
          "sha256-+6PhbDzUn0e4sQgsUs/kF0C5HlMOixZvlNolO9a4VdI="
        else
          "sha256-hTlIJMcf3vi8qbJLKR0Txc1a5BOYYjkPc6YWTwCiEEc=";
    };
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    installPhase = ''
      install -Dm555 -t $out/bin package/bin/jscpd
    '';
  };
in
{
  # Disable automatic .env loading so agent shells stay deterministic.
  # NOTE: do not pass `-O dotenv.enable:bool false` on the command line:
  # combined with the out-of-tree binding, current devenv drops the whole
  # profile from PATH. This declaration replaces that flag.
  dotenv.enable = false;

  # Tools available in the shell. Add project tooling here instead of
  # installing packages globally.
  packages = [
    jscpd # token-clone scanner, pinned rust binary (see above)
    # Complexity-gate tool. CAVEAT (msks pattern): nixpkgs' xenon runs
    # on its own python, whose parser can reject syntax a newer project
    # python writes, silently skipping files. xenon-gate.sh turns any
    # skip into a hard failure, so the breakage is loud; if the project
    # python is newer than xenon's, rebuild xenon against the project
    # python like msks does:
    #   (pkgs.callPackage (pkgs.path + "/pkgs/by-name/xe/xenon/package.nix")
    #     { python3 = config.languages.python.package; })
    pkgs.xenon
    pkgs.ruff
  ];

  # Environment variables exported into the shell.
  env = { };

  # Languages — EXAMPLE configuration: this devenv is configured against
  # the sample Python project in sample/. A real project replaces this
  # block with its own stack and drops the PYTHONPATH line in
  # enterShell (real projects install their package: uv sync, or
  # `pip install -e .` once inside the shell).
  languages.python = {
    enable = true;
    # A venv under .devenv/state; the shell's `python` is the venv's.
    venv.enable = true;
  };

  # Hook that runs on every `devenv shell`.
  enterShell = ''
    # Generated (not committed) so hand-run prettier skips what the hook
    # skips: machine-managed lock files and devenv state.
    cat > "$DEVENV_ROOT/.prettierignore" <<'PRETTIER'
    *.lock
    .devenv/
    PRETTIER
    # EXAMPLE (goes with the languages.python block): make the sample
    # project importable under the venv's python, live (no copy to the
    # nix store). Real projects replace this with a real install.
    export PYTHONPATH="$DEVENV_ROOT/sample/src''${PYTHONPATH:+:$PYTHONPATH}"
  '';

  # Template-owned scripts, wired from nix/scripts/. They become
  # commands inside the shell (e.g. `devenv shell -- hello`).
  scripts.hello = {
    description = "Example template script; shows cwd and DEVENV_ROOT";
    exec = "${./scripts/hello.sh}";
  };

  # WORKAROUND (devenv 2.3.x, msks/klangk #3444 pattern): the RunMode::All
  # scheduler adds prerequisites of every visited task — including the
  # skipped devenv:enterTest, whose prerequisite devenv:git-hooks:run is
  # the full hook suite — so a failing hook aborts `devenv shell` before
  # it opens. Clearing the `before` edge keeps the suite out of the
  # shell's task graph (mkForce replaces the upstream list; a plain
  # `before = [ ]` concatenates and changes nothing). The commit-time
  # hook keeps enforcing the suite on `git commit`. Remove once an
  # upstream release stops scheduling prerequisites of skipped tasks.
  tasks."devenv:git-hooks:run" = lib.mkIf config.git-hooks.enable {
    before = lib.mkForce [ ];
  };

  # --- Pre-commit hooks: the msks set by default ---
  # Runs at commit time (not on shell entry, see the task workaround
  # above). The script-based gates grade the file set configured as
  # GATE_GLOBS inside each gate script in nix/scripts/ — the
  # configuring agent points those at this project's Python package,
  # or deletes gates the project does not want.
  git-hooks.hooks = {
    # Python: ruff lint + format (no-op on non-Python projects)
    ruff-lint = {
      enable = true;
      name = "ruff check";
      entry = "${pkgs.ruff}/bin/ruff check --fix";
      files = "\\.py$";
      language = "system";
      pass_filenames = true;
    };
    ruff-format = {
      enable = true;
      name = "ruff format";
      entry = "${pkgs.ruff}/bin/ruff format";
      files = "\\.py$";
      language = "system";
      pass_filenames = true;
    };
    # Complexity gate: rank A everywhere. pass_filenames = false — the
    # hook grades the full gate set via nix/scripts/xenon-gate.sh
    # (a staged subset's average can exceed rank A while the whole tree
    # passes); `files` stays as the run trigger.
    xenon = {
      enable = true;
      name = "xenon";
      entry = "nix/scripts/xenon-gate.sh";
      files = "\\.py$";
      language = "system";
      pass_filenames = false;
    };
    # Lines gate: no module past the ceiling the gate script carries
    # (1000 today; it only goes down). Over-ceiling files live on the
    # shrinking nix/scripts/lines-exemptions.txt list, which also
    # triggers the hook — a list edit is exactly when the gate should
    # re-run. Whole-tree like xenon above; `files` stays as the trigger.
    lines-gate = {
      enable = true;
      name = "lines-gate";
      entry = "bash nix/scripts/lines-gate.sh";
      files = "\\.py$|nix/scripts/lines-exemptions\\.txt$";
      language = "system";
      pass_filenames = false;
    };
    # Token-clone gate: no exact clone of >= 70 tokens. pass_filenames
    # = false — cross-file clones only show when the whole tree is
    # scanned (a staged subset can hide them); `files` stays as the
    # run trigger.
    jscpd = {
      enable = true;
      name = "jscpd";
      entry = "nix/scripts/jscpd-gate.sh";
      files = "\\.py$";
      language = "system";
      pass_filenames = false;
    };
    # Deferred-imports gate: imports live at module scope. Plain
    # top-level, ``if TYPE_CHECKING:`` blocks, and module-scope
    # ``try/except ImportError`` guards are exempt; ``# allow-deferred-import``
    # suppresses an individual import. Staged files are mapped to their
    # package roots, so the hook scans whole packages. The interpreter
    # is pinned by store path, NOT a bare `python3`: pre-commit prepends
    # its own interpreter's bin to hook PATHs, which may not parse the
    # project's syntax — under a bare `python3` the checker silently
    # skipped whole packages and passed vacuously (found in msks review).
    # require_serial: one invocation with all files — pass_filenames
    # maps them to package roots, and chunked invocations would rescan
    # (and re-print) the same packages once per chunk.
    deferred-imports = {
      enable = true;
      name = "deferred-imports";
      entry = "${config.languages.python.package}/bin/python nix/scripts/check_deferred_imports.py";
      files = "\\.py$";
      language = "system";
      pass_filenames = true;
      require_serial = true;
    };
    # Import-cycle gate over the package's import graph. Whole-tree
    # check, so pass_filenames = false; `files` is the run trigger,
    # matching the xenon idiom above.
    import-cycles = {
      enable = true;
      name = "import-cycles";
      entry = "${config.languages.python.package}/bin/python nix/scripts/check_import_cycles.py";
      files = "\\.py$";
      language = "system";
      pass_filenames = false;
    };
    # Shell: format + static analysis + shebang guard on executables
    shfmt.enable = true;
    shfmt.settings.indent = 2;
    check-executables-have-shebangs.enable = true;
    shellcheck.enable = true;
    # Markdown lint. prettier owns formatting; markdownlint stays a
    # lint-only gate. The disabled rules are the prettier-owned ones
    # (line length, bare URLs, table-pipe alignment), so a
    # prettier-formatted file always passes and the hooks cannot
    # ping-pong. Keep new rules inside that invariant.
    markdownlint.enable = true;
    markdownlint.settings.configuration = {
      MD013 = false;
      MD024.siblings_only = true;
      MD034 = false;
      MD060 = false;
    };
    # GitHub Actions workflows
    actionlint.enable = true;
    # Secrets: only credentials that verify live fail the commit;
    # key-shaped fixtures stay green and offline runs degrade to a pass.
    trufflehog = {
      enable = true;
      name = "trufflehog";
      entry = "${pkgs.trufflehog}/bin/trufflehog filesystem --fail --results=verified";
      language = "system";
      pass_filenames = true;
    };
    # Nix
    nixfmt.enable = true;
    nixfmt.settings.width = 80;
    # TOML: every staged TOML file must parse
    check-toml.enable = true;
    # YAML: relaxed preset, lines up to 200 columns, warnings non-fatal
    yamllint.enable = true;
    yamllint.settings = {
      configuration = ''
        extends: relaxed
        rules:
          line-length:
            max: 200
      '';
      strict = false;
    };
    # JS/TS/JSON/YAML/Markdown formatting: rewrite in place; unknown
    # file types are skipped; lock files excluded. A run that rewrites
    # fails once with "files were modified"; the re-staged run validates
    # the final bytes.
    prettier = {
      enable = true;
      settings.write = true;
      excludes = [ "\\.lock$" ];
    };
  };
}
