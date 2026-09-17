# Installation

Patou is a single Rust binary. You only need it installed globally if you
want to run `patou init`, `patou install`, or `patou check` directly —
contributors who just clone a repository that already has Patou set up
don't need to install anything (see [How hooks work](./hooks.md)).

## Prebuilt binary (recommended)

Every [release](https://github.com/CM-exe/patou/releases) publishes
binaries for Linux, macOS (Intel and Apple Silicon), and Windows. Install
scripts fetch the right one automatically and don't need a Rust
toolchain:

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.sh | sh
```

```powershell
# Windows PowerShell
irm https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.ps1 | iex
```

```cmd
:: Windows cmd.exe (no PowerShell required — uses curl and tar,
:: both built into Windows 10 1803+ and Windows 11)
curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.cmd -o install.cmd && install.cmd
```

By default this installs to `~/.local/bin` (`%LOCALAPPDATA%\Patou\bin` on
Windows) — set `PATOU_INSTALL_DIR` to change that, and `PATOU_VERSION`
(e.g. `v0.2.0`) to install a specific release instead of the latest one.

Piping a downloaded script into a shell requires trusting its source; the
scripts are plain, short, and versioned in the repository under
[`scripts/`](https://github.com/CM-exe/patou/tree/main/scripts) if you'd
rather read them first or download and run them locally.

### "Open Patou bash here" (Windows)

On Windows, `install.ps1`/`install.cmd` also install `patou-bash.exe` and
add an **Open Patou bash here** entry to the folder right-click menu.
This adds a one-time ~60 MB download (Git for Windows' portable
distribution, see below) on top of the plain `patou.exe` install; set
`PATOU_SKIP_BASH_HERE` to skip it and install just `patou.exe`.

`patou-bash.exe` is a small native launcher, built from its own package
in the repository
([`patou-bash/`](https://github.com/CM-exe/patou/tree/main/patou-bash),
a `cargo build` workspace member alongside the main `patou` package)
using [`assets/favicon.ico`](https://github.com/CM-exe/patou/blob/main/assets/favicon.ico)
as its icon like any other installed app. Uninstalling removes the
binary, the bundled Git for Windows copy, and the menu entry again.

It's self-contained rather than depending on a system-wide Git for
Windows install: `install.ps1`/`install.cmd` download Git for Windows'
official "PortableGit" distribution once (see `PATOU_GIT_TAG` /
`PATOU_GIT_ASSET` in each script to pin a different release) and extract
it into a private `git\` folder next to `patou-bash.exe`. Rather than
reimplementing what launching Git Bash involves, patou-bash.exe reuses
Git for Windows' own launcher from that folder, `git-bash.exe` — the
same binary and `--cd=<dir>` argument the official installer's own "Git
Bash Here" shortcut uses — and layers Patou's banner and mintty color
theme on through Git for Windows' own customization points (an
`etc/profile.d/*.sh` script, sourced automatically by every login shell,
and `etc/minttyrc`, mintty's default config file), applied only to its
own private copy so a fallback to a system-wide install (see below)
isn't left with Patou's branding. The result: an ordinary Git Bash
session, with the install directory already on `PATH` (so `patou` is
available even if you haven't added it to `PATH` globally) and a
grey/blue/light-blue mintty color theme in place of Git Bash's default
yellow/green palette.

If the bundled copy is ever missing (a broken install, or
`patou-bash.exe` run from somewhere else entirely), it falls back to
looking for a system-wide install instead of doing nothing — the
registry key the official installer writes, common install directories,
then `git --exec-path`/`where git.exe` for anything else with `git` on
`PATH` — and leaves it exactly as Git for Windows configured it, since
that copy is shared with the user's own everyday Git Bash use.

## From source

```bash
git clone https://github.com/CM-exe/patou.git
cd patou
cargo install --path .
```

This puts `patou` on your `PATH` (in `~/.cargo/bin` by default).

## Build only, without installing

If you just want to build once and use the binary from the repository
without installing it globally:

```bash
cargo build --release
./target/release/patou --help
```

## Requirements

- A recent Rust toolchain (edition 2024) to build from source.
- `git` available on `PATH` — Patou shells out to it for repository
  discovery and configuration.

## Uninstall

How to remove `patou` depends on how you installed it.

**Installed with the install script or `.cmd`/`.ps1` above:**

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/uninstall.sh | sh
```

```powershell
# Windows PowerShell
irm https://raw.githubusercontent.com/CM-exe/patou/main/scripts/uninstall.ps1 | iex
```

```cmd
:: Windows cmd.exe
curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/uninstall.cmd -o uninstall.cmd && uninstall.cmd
```

Each removes the `patou` binary from its install directory — set
`PATOU_INSTALL_DIR` if you installed to a non-default location — and, on
Windows, also removes the "Open Patou bash here" context menu entry if
`install.ps1`/`install.cmd` added one.

**Installed with `cargo install --path .`:**

```bash
cargo uninstall patou
```

**Built locally without installing** (`cargo build --release`): just
delete the `target/` directory, or the repository clone.

### Removing Patou from a repository

Uninstalling the `patou` binary is unrelated to a repository that already
has Patou set up — that's local state living in `.patou/` and Git config,
not something the binary needs to be present to remove:

```bash
git config --unset core.hooksPath   # stop enforcing the hooks
rm -rf .patou                       # also drop the rules and hook scripts
```

If you only want to pause enforcement temporarily without removing
anything, the `git config --unset` step alone is enough.
