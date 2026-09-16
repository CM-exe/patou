# `patou init`

```bash
patou init
```

Initializes Patou in the current Git repository. Must be run with
`patou` available (installed globally, or built locally — see
[Installation](../installation.md)); it's meant to be run once by
whoever sets Patou up for a project.

## What it does

1. Finds the repository root (`git rev-parse --show-toplevel`).
2. Creates `.patou/config.toml` with a default `[commit]` rule (see
   [Configuration](../configuration.md)).
3. Creates `.patou/hooks/commit-msg`, a self-contained shell script (see
   [How hooks work](../hooks.md)).
4. Creates `.patou/install`, `.patou/install.cmd`, and `.patou/install.ps1`
   — activation scripts for Linux/macOS/Git Bash, Windows cmd.exe, and
   Windows PowerShell respectively.
5. Runs `git config core.hooksPath .patou/hooks` for the current clone.

## Idempotency

Re-running `patou init` never overwrites existing files — it skips
anything already present and prints which files were skipped. It's safe
to run again, e.g. after upgrading `patou`, to pick up newly-added
scaffold files without touching your customized `config.toml`.

## After running it

Commit `.patou/`:

```bash
git add .patou
git commit -m "chore: set up patou"
```

Contributors who clone the repository afterwards only need to run
[`.patou/install`](./install.md) — no global `patou` install required.
