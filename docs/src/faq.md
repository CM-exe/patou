# FAQ

### Do contributors need to install `patou`?

No. Once someone has run `patou init` and committed `.patou/`, anyone who
clones the repository only needs to run `.patou/install` (or the
`.cmd`/`.ps1` variant on Windows) — no `patou` binary required. See
[How hooks work](./hooks.md).

### What does `patou init` need that contributors don't?

The `patou` binary itself — to scaffold `.patou/` in the first place.
After that, the generated files are all plain text and shell, with no
further dependency on the binary for enforcement.

### Can I change the commit-message rule?

Yes — edit `.patou/config.toml`. See [Configuration](./configuration.md),
and make sure to keep `pattern` as a single-quoted TOML literal string.

### What if I don't want commit-message linting at all?

Remove the `[commit]` table from `.patou/config.toml` (or leave it out of
a hand-written config). Both `patou check` and the hook then skip
validation and exit successfully.

### Does the hook run in CI?

Git hooks are a client-side (local `.git`) mechanism — they don't run
automatically in most CI systems, which typically do a fresh clone
without carrying over local Git config. If you want the same validation
in CI, install `patou` there and run `patou check` explicitly (e.g.
against the message of the commit or PR being built).

### Why not just use Husky / commitlint / pre-commit?

Those are great tools, but they pull in a Node.js or Python toolchain as
a project dependency just to lint commit messages. Patou's hook has zero
runtime dependencies beyond `git` and a POSIX shell, which is already a
requirement for having Git hooks at all.
