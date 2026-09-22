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

## Why this name?

The name **Patou** comes from the **Great Pyrenees**, a large mountain dog
traditionally used by shepherds to guard and protect flocks of sheep.

That idea is at the heart of this project. Just like a Patou watches over a
flock, **Patou watches over your Git repository**. It stays close to the
project, enforces its rules, and helps prevent invalid commits from making
their way into the codebase.

The project was also born from a simple frustration with existing Git hook
and quality tools. Many popular solutions rely on Node.js, npm, or other
project-specific runtimes and dependencies. While those tools can be
powerful, they can also add setup and maintenance overhead to projects that
simply need a reliable way to enforce a few Git rules.

Patou takes a different approach:

- 🐕 **It stays with the repository** — configuration and rules can be
  version-controlled alongside the code.
- 🦀 **It is built in Rust** — distributed as a fast, standalone executable.
- 📦 **It has no Node.js or npm dependency** — and does not require a
  project-specific runtime.
- 🔒 **It protects the development workflow** — by validating commits before
  they reach the repository.
- 🪶 **It aims to stay lightweight** — simple to install, configure, and
  carry from project to project.

In short, **Patou is a small guard for your Git workflow**: close to the
project, easy to deploy, and there when you need it.

## What it does today

- `patou init` — scaffolds `.patou/` in a Git repository: the rules file,
  the Git hook, and cross-platform activation scripts.
- `patou install` — activates the hooks for one clone (points Git's
  `core.hooksPath` at `.patou/hooks`).
- `patou check` — validates a commit message against the configured
  rules; this is what the hook and CI can call.

See [Getting started](./getting-started.md) to try it in a repository.
