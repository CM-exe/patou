# Configuration

Rules live in `.patou/config.toml`, created by `patou init` and versioned
with the repository.

## `[commit]`

```toml
[commit]
pattern = '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9-]+\))?: .{1,72}$'
```

- `pattern` — a regular expression matched against the commit **subject**
  (the first non-empty, non-comment line of the message). Both
  `patou check` and the shell `commit-msg` hook validate against it.
  The default enforces
  [Conventional Commits](https://www.conventionalcommits.org/)-style
  subjects: `type(scope): subject`, scope optional.

### Use a TOML literal string

Always write `pattern` as a single-quoted TOML **literal** string, not a
double-quoted basic string. Literal strings don't process backslash
escapes, so a regex like `\(` (escaping a literal parenthesis) is written
exactly as `\(` in the file — no doubling backslashes needed, and no risk
of the Rust binary and the shell hook parsing two different regexes from
the same-looking configuration. See [How hooks work](./hooks.md) for why
this matters.

### No `[commit]` rule

If `.patou/config.toml` has no `[commit]` table, both `patou check` and
the hook skip commit-message validation entirely (useful while you're
still deciding on a rule, or if commit-message linting isn't what you
want).

## `[branch]`

Added by `patou init -b`/`--branch` (or `-a`/`--all`); see
[`patou init`](./commands/init.md).

```toml
[branch]
pattern = '^(main|develop|dev|(feature|fix|hotfix|refactor|chore|docs)/[a-zA-Z0-9._/-]+)$'
```

- `pattern` — a regular expression matched against the current branch
  name (`git symbolic-ref --short HEAD`). Enforced by the
  `.patou/hooks/pre-commit` hook on every commit; a detached `HEAD`
  (e.g. mid-rebase) is skipped rather than rejected, since there's no
  branch to validate. The default allows:
  - `main`
  - `develop` / `dev` — drop these two from the pattern if your workflow
    has no long-lived integration branch
  - `<type>/<description>` for `feature`, `fix`, `hotfix`, `refactor`,
    `chore`, and `docs` branches

There's no `patou check` equivalent for `[branch]` — it's only validated
by the hook itself.

## `[tag]`

Added by `patou init -t`/`--tag` (or `-a`/`--all`); see
[`patou init`](./commands/init.md).

```toml
[tag]
pattern = '^(v[0-9]+\.[0-9]+\.[0-9]+|(build|deploy|release)/[a-zA-Z0-9._/-]+)$'
```

- `pattern` — a regular expression matched against each tag name being
  pushed. Enforced by the `.patou/hooks/pre-push` hook: unlike commits or
  branches, Git has no hook that fires when a tag is *created* locally,
  so `[tag]` is validated at the last point before it leaves the machine
  — when it's pushed. A push containing even one non-conforming tag is
  rejected in its entirety. The default allows:
  - Semantic version tags: `v<MAJOR>.<MINOR>.<PATCH>` (e.g. `v1.4.0`)
  - `<type>/<description>` for `build`, `deploy`, and `release` tags

There's no `patou check` equivalent for `[tag]` either, for the same
reason as `[branch]`.

## What's next

`[branch]` and `[tag]` follow the same shape as `[commit]` on purpose —
a single `pattern` key, matched with `grep -E` in shell and the Rust
`regex` crate wherever a Rust-side check exists — so future rule types
can slot in the same way.
