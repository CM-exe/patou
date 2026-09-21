# `patou init`

```bash
patou init [-b|--branch] [-t|--tag] [-a|--all]
```

Initializes Patou in the current Git repository. Must be run with
`patou` available (installed globally, or built locally — see
[Installation](../installation.md)); it's meant to be run once by
whoever sets Patou up for a project.

## Flags

| Flag | Adds | Enforced by |
| --- | --- | --- |
| *(none)* | `[commit]` rule only | `.patou/hooks/commit-msg` |
| `-b`, `--branch` | `[branch]` rule | `.patou/hooks/pre-commit` |
| `-t`, `--tag` | `[tag]` rule | `.patou/hooks/pre-push` |
| `-a`, `--all` | every rule above (`-b -t`) | all of the above |

The `[commit]` rule is always included — it's the baseline every `init`
has written since the beginning. `[branch]` and `[tag]` are opt-in because
not every project wants them; see [Configuration](../configuration.md)
for what each default pattern looks like.

## What it does

1. Finds the repository root (`git rev-parse --show-toplevel`).
2. Creates or updates `.patou/config.toml` with the rule sections this
   invocation asked for (see [Idempotency](#idempotency) below for what
   "updates" means).
3. Creates `.patou/hooks/commit-msg` unconditionally, and
   `.patou/hooks/pre-commit`/`.patou/hooks/pre-push` when the `[branch]`/
   `[tag]` rule ends up present — all self-contained shell scripts (see
   [How hooks work](../hooks.md)).
4. Creates `.patou/install`, `.patou/install.cmd`, and `.patou/install.ps1`
   — activation scripts for Linux/macOS/Git Bash, Windows cmd.exe, and
   Windows PowerShell respectively.
5. Runs `git config core.hooksPath .patou/hooks` for the current clone.

## Idempotency

Re-running `patou init` never overwrites an existing file, and never
reorders or rewrites what's already in `config.toml` — it's safe to run
again, e.g. after upgrading `patou`, to pick up newly-added scaffold
files without touching your customized rules.

`config.toml` gets one extra behavior on top of that: if it already
exists and this invocation wants a rule section it doesn't have yet (for
example, running `patou init -b` in a repository that only ran plain
`patou init` before, or a `[commit]` table that got hand-deleted), you're
prompted interactively:

```
config.toml is missing the [branch] rule - add the default branch naming pattern? [y/N]
```

Answering `y`/`yes` appends the default block for that rule to the end of
the file and, if applicable, writes the matching hook. Anything else (or
running non-interactively with no input piped in) leaves the file
untouched — nothing is ever added without an explicit yes.

## After running it

Commit `.patou/`:

```bash
git add .patou
git commit -m "chore: set up patou"
```

Contributors who clone the repository afterwards only need to run
[`.patou/install`](./install.md) — no global `patou` install required.
