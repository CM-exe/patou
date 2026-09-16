# Introduction

<p align="center">
  <img src="./assets/logo-patou.png" alt="Patou logo" width="360">
</p>

**Patou** is a lightweight, self-contained Git quality tool built in Rust.
It embeds version-controlled commit rules and pre-commit validation
directly into your repository — no global installation, Node.js, or
project-specific dependencies required.

**Clone the repository, get the rules, follow the same standards.**

## Why Patou

Most commit-linting tools (commitlint, Husky, pre-commit) need a Node.js
or Python toolchain installed on every contributor's machine, plus a
`package.json`/`requirements.txt` living in the project. Patou takes a
different approach:

- Rules live in a single `.patou/config.toml`, versioned with the project.
- The Git hook that enforces them is a small, dependency-free shell
  script — it doesn't call out to the `patou` binary, so a contributor who
  only clones the repository doesn't need to install anything to get
  working, enforced rules.
- The `patou` binary itself is only needed by the person scaffolding
  Patou into a repository (`patou init`), or by anyone who wants to run
  checks manually or in CI.

## What it does today

- `patou init` — scaffolds `.patou/` in a Git repository: the rules file,
  the Git hook, and cross-platform activation scripts.
- `patou install` — activates the hooks for one clone (points Git's
  `core.hooksPath` at `.patou/hooks`).
- `patou check` — validates a commit message against the configured
  rules; this is what the hook and CI can call.

See [Getting started](./getting-started.md) to try it in a repository.
