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

On Windows, `install.ps1`/`install.cmd` also install `patou-bash.exe`,
add an **Open Patou bash here** entry to the folder right-click menu, and
add a **Patou Bash** shortcut to the Start Menu (so it shows up when
searching the Start Menu, like any other installed app). This adds a
one-time, fairly large (~150–300 MB) download on top of the plain
`patou.exe` install; set `PATOU_SKIP_BASH_HERE` to skip all of it and
install just `patou.exe`.

`patou-bash.exe` is a small native launcher, built from its own package
in the repository
([`patou-bash/`](https://github.com/CM-exe/patou/tree/main/patou-bash),
a `cargo build` workspace member alongside the main `patou` package)
using [`assets/favicon.ico`](https://github.com/CM-exe/patou/blob/main/assets/favicon.ico)
as its icon like any other installed app. Uninstalling removes the
binary, the bundled MSYS2 install, the menu entry, and the Start Menu
shortcut again.

It's self-contained rather than depending on a system-wide Git for
Windows install: `install.ps1`/`install.cmd` download a prebuilt
[MSYS2](https://www.msys2.org/) + `git` bundle (not Git for Windows' own
copy) into a private `msys64\` folder next to `patou-bash.exe`. That
bundle is built in CI by
[`.github/workflows/msys2-bundle.yml`](https://github.com/CM-exe/patou/blob/main/.github/workflows/msys2-bundle.yml)
— using the official
[`msys2/setup-msys2`](https://github.com/msys2/setup-msys2) GitHub
Action to set up MSYS2 and `pacman`-install `git` into it — and
published as `patou-msys2-x86_64.zip`, an asset
on that **same patou release**, right alongside `patou-<target>.zip`.
The install scripts fetch it using the exact same version they're
installing (`PATOU_VERSION`/`latest`), just like the main download —
just a download and extract, no `pacman`, no bootstrap, on the machine
being installed to. Building it only starts once that release actually
exists (triggered by the Release workflow *completing*, not by the same
tag push release.yml reacts to), since attaching to it requires it to
already be there; see `PATOU_MSYS2_BUNDLE_URL` in each script to point
at a different bundle instead. This keeps both install scripts free of a
PowerShell dependency for this step too (`install.cmd` needed a
generated `.ps1` for the bootstrap when it ran locally; a plain
download+extract doesn't).

From that bundled install, patou-bash.exe launches its `mintty.exe`
directly, using the same invocation Git for Windows' own `git-bash.exe`
uses internally (`--nodaemon -o AppID=... -i <icon>
--store-taskbar-properties -- bash --login -i`) but with Patou's own
name and icon in place of Git's — `git-bash.exe` itself can't be reused
as-is for this, since it hardcodes its own icon on the command line
regardless of what launched it. Patou's banner and mintty color theme
are layered on through this same MSYS/Cygwin-style customization
mechanism (an `etc/profile.d/*.sh` script, sourced automatically by
every login shell, and `etc/minttyrc`, mintty's default config file).
The result: a window titled "Patou Bash", using
[`assets/favicon.ico`](https://github.com/CM-exe/patou/blob/main/assets/favicon.ico)
as its icon (both in the window/taskbar and for taskbar grouping —
mintty's `-i` accepts any executable with an icon resource, and
`patou-bash.exe` is one, via `build.rs`), with the install directory
already on `PATH` (so `patou` is available even if you haven't added it
to `PATH` globally) and a grey/blue/light-blue mintty color theme in
place of Git Bash's default yellow/green palette. Inside a Git repo, the
prompt also shows the current branch next to the path — white normally,
or light blue if that repo has a `.patou/` directory too.

If the bundled MSYS2 install is ever missing (setup failed, or
`patou-bash.exe` run from somewhere else entirely), it falls back to
looking for a *system-wide Git for Windows* install instead of doing
nothing — the registry key the official installer writes, common
install directories, then `git --exec-path`/`where git.exe` for anything
else with `git` on `PATH`. That fallback reuses the system install's own
`git-bash.exe` exactly as configured, deliberately without Patou's
branding, since it's shared with the user's own everyday Git Bash use.

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
Windows, also removes the "Open Patou bash here" context menu entry and
Start Menu shortcut if `install.ps1`/`install.cmd` added them.

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
