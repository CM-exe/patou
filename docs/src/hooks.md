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

## The hook itself is plain shell

`.patou/hooks/commit-msg` does **not** call the `patou` binary. It reads
the pattern straight out of `.patou/config.toml` and validates the commit
subject with `grep -E`, using only POSIX shell, `grep`, and `sed`:

```sh
#!/bin/sh
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config="$dir/../config.toml"
# ...extracts `pattern` from config.toml and greps the commit subject...
```

Because of this, the hook that Git actually invokes on every commit works
on any machine with `git` and a POSIX shell — which is guaranteed,
because that's also what's needed to run Git hooks at all.

## The pattern is a TOML *literal* string

`config.toml` stores the regex pattern as a single-quoted TOML literal
string:

```toml
[commit]
pattern = '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9-]+\))?: .{1,72}$'
```

TOML literal strings don't process backslash escapes, so the bytes stored
in the file are exactly the regex Patou uses — both the Rust `regex`
crate (used by `patou check`) and the shell hook's `grep -E` read the
*same* bytes, with no double-escaping to keep in sync.

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
