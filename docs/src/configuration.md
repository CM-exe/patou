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

## What's next

Patou's rule set is intentionally minimal today — a single commit-message
pattern. The `[commit]` table structure leaves room to grow into
additional rule types without breaking existing configuration.
