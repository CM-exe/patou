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

By default this installs to `~/.local/bin` (`%LOCALAPPDATA%\Patou\bin` on
Windows) — set `PATOU_INSTALL_DIR` to change that, and `PATOU_VERSION`
(e.g. `v0.2.0`) to install a specific release instead of the latest one.

Piping a downloaded script into a shell requires trusting its source; the
scripts are plain, short, and versioned in the repository under
[`scripts/`](https://github.com/CM-exe/patou/tree/main/scripts) if you'd
rather read them first or download and run them locally.

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
