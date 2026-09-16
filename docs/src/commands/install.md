# `patou install`

```bash
patou install
```

Activates Patou's hooks for the current clone of a repository that was
already set up with [`patou init`](./init.md) — i.e. `.patou/config.toml`
and `.patou/hooks/` already exist and are tracked by Git.

## What it does

Runs `git config core.hooksPath .patou/hooks`. That's it. `core.hooksPath`
lives in `.git/config`, which isn't part of the repository's tracked
content, so it doesn't survive `git clone` — every fresh clone needs to
set it once.

If `.patou/hooks` doesn't exist, `install` fails with a message pointing
to `patou init`.

## Without a global `patou` install

This is the one command a contributor who *only* cloned the repository
needs to run — and they don't need the `patou` binary to run it. Three
equivalent scripts ship in `.patou/` for exactly this purpose:

```bash
# Linux, macOS, or Git Bash on Windows
.patou/install
```

```cmd
:: Windows cmd.exe
.patou\install.cmd
```

```powershell
# Windows PowerShell
.\.patou\install.ps1
```

Each does the same single `git config` call as `patou install`, using
only tools guaranteed to be available wherever Git itself runs.

> PowerShell's default execution policy may block running local scripts.
> If `.\.patou\install.ps1` is refused, run
> `powershell -ExecutionPolicy Bypass -File .patou\install.ps1` instead,
> or adjust your execution policy. See
> [Platform support](../platform-support.md).
