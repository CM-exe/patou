# Installation

Patou is a single Rust binary. You only need it installed globally if you
want to run `patou init`, `patou install`, or `patou check` directly —
contributors who just clone a repository that already has Patou set up
don't need to install anything (see [How hooks work](./hooks.md)).

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
