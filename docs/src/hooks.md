# How hooks work

Patou's core design goal is that **enforcement never depends on a global
`patou` install**. Here's how that's achieved.

## `core.hooksPath`, not `.git/hooks`

`patou init` points Git at a versioned hooks directory instead of the
default, untracked `.git/hooks`:

```bash
git config core.hooksPath .patou/hooks
```

This setting is per-clone (it lives in `.git/config`, which `git clone`
never copies), which is why every clone needs to run an activation step
once — that's the whole job of [`patou install`](./commands/install.md)
and its script equivalents.

## The hooks themselves are plain shell

None of `.patou/hooks/commit-msg`, `.patou/hooks/pre-commit`, or
`.patou/hooks/pre-push` call the `patou` binary. Each reads the relevant
pattern straight out of `.patou/config.toml` and validates with
`grep -E`, using only POSIX shell, `grep`, `sed`, and (for the two rules
added after `[commit]`) `awk`:

```sh
#!/bin/sh
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config="$dir/../config.toml"
# ...extracts `pattern` from config.toml and greps the commit subject...
```

Because of this, the hooks Git actually invokes work on any machine with
`git` and a POSIX shell — which is guaranteed, because that's also what's
needed to run Git hooks at all.

| Hook | Fires on | Validates | Added by |
| --- | --- | --- | --- |
| `commit-msg` | every commit | the commit subject | `patou init` (always) |
| `pre-commit` | every commit | the current branch name | `patou init -b`/`--branch` |
| `pre-push` | every `git push` | tag names among the pushed refs | `patou init -t`/`--tag` |

### Why branch and tag validation live on different hooks

Git has no hook that fires when a branch or tag is *created* locally —
`git branch`/`git checkout -b`/`git tag` don't invoke anything. Each rule
is enforced at the earliest point Git *does* hand control to a hook where
the thing being validated is observable:

- **Branches** are checked in `pre-commit`, since the current branch is
  always known there and it runs on every commit regardless of which
  branch you're on. A detached `HEAD` (mid-rebase, checked-out tag, etc.)
  is skipped rather than rejected — there's no branch name to validate.
- **Tags** are checked in `pre-push`, the hook Git runs just before
  transferring refs to a remote, which receives one
  `<local ref> <local sha> <remote ref> <remote sha>` line per pushed ref
  on stdin. The hook filters for `refs/tags/*` local refs and validates
  the tag name after that prefix; anything else (branch pushes, etc.) is
  left alone. A push containing any non-conforming tag is rejected as a
  whole, before anything reaches the remote.

### Extracting the right `pattern`

Once `[branch]` and/or `[tag]` are configured alongside `[commit]`,
`config.toml` can have up to three lines starting with `pattern`. The
`commit-msg` hook still gets away with a plain
`grep '^pattern' | head -n1` because `[commit]` is always written first
in the file — but `pre-commit` and `pre-push` can't rely on ordering, so
each scopes its extraction to its own section with a small `awk` pass
(stop looking once the next `[...]` header is hit):

```sh
awk '
  /^\[branch\]/ { in_section=1; next }
  /^\[/ { in_section=0 }
  in_section && /^pattern[[:space:]]*=/ { print; exit }
' "$config"
```

## The pattern is a TOML *literal* string

`config.toml` stores every regex pattern as a single-quoted TOML literal
string:

```toml
[commit]
pattern = '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9-]+\))?: .{1,72}$'
```

TOML literal strings don't process backslash escapes, so the bytes stored
in the file are exactly the regex Patou uses — both the Rust `regex`
crate (used by `patou check` for `[commit]`) and each shell hook's
`grep -E` read the *same* bytes, with no double-escaping to keep in sync.

## Why `patou` is still useful

The compiled binary remains the tool for:

- `patou init` — scaffolding `.patou/` in the first place.
- `patou check <file>` — validating a message manually, or from CI, with
  richer error messages (invalid config, invalid regex, etc.) than the
  hook's minimal shell logic provides.
- `patou install` — the same activation the shell scripts perform, for
  anyone who already has the binary.

See [Platform support](./platform-support.md) for the exact guarantees on
Linux, macOS, and Windows.
