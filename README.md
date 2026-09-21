<div align="center">

<img src="assets/logo-patou.png" alt="Patou logo" width="420">

# Patou

[![GitHub release](https://img.shields.io/github/v/release/CM-exe/patou)](https://github.com/CM-exe/patou/releases)

</div>

A lightweight, self-contained Git quality tool built in Rust. Patou embeds version-controlled commit rules and pre-commit validation directly into your repository—no global installation, Node.js, or project-specific dependencies required.

**Clone the repository, get the rules, follow the same standards.**

* 🚀 Fast, cross-platform Rust executable
* 🔒 Repository-defined and version-controlled rules
* 🪝 Automatic pre-commit validation
* 📦 Self-contained with no Node.js/npm dependency
* 🧩 Extensible with custom rules, formatters, linters, and Git checks

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.sh | sh
```

```powershell
irm https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.ps1 | iex
```

```cmd
curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.cmd -o install.cmd && install.cmd
```

See the [documentation](https://cm-exe.github.io/patou/) for other
install methods, uninstalling, configuration, and how the hooks work.

## Usage

```bash
patou init

patou install

patou check
```

---

## 🐕 Why Patou?

The name **Patou** comes from the **Great Pyrenees**, a large mountain dog traditionally used by shepherds to guard and protect flocks of sheep.

That idea is at the heart of this project.

Just like a Patou watches over a flock, **Patou watches over your Git repository**. It stays close to the project, enforces its rules, and helps prevent invalid commits from making their way into the codebase.

The project was also born from a simple frustration with existing Git hook and quality tools. Many popular solutions rely on **Node.js, npm, or other project-specific runtimes and dependencies**. While those tools can be powerful, they can also add setup and maintenance overhead to projects that simply need a reliable way to enforce a few Git rules.

Patou takes a different approach:

* 🐕 **It stays with the repository** — configuration and rules can be version-controlled alongside the code.
* 🦀 **It is built in Rust** — distributed as a fast, standalone executable.
* 📦 **It has no Node.js or npm dependency** — and does not require a project-specific runtime.
* 🔒 **It protects the development workflow** — by validating commits and other Git operations before they reach the repository.
* 🪶 **It aims to stay lightweight** — simple to install, simple to configure, and easy to carry from project to project.

In short, **Patou is a small guard for your Git workflow**: close to the project, easy to deploy, and there when you need it.

---

## 🗺️ Roadmap

### Git Hooks

 - [X] Support common Git hooks (pre-commit, commit-msg, pre-push, etc.)
 - [X] Make hook installation simple and reliable
 - [ ] Support custom hook scripts
 - [ ] Support multiple commands per hook
 - [X] Provide clear error messages and exit codes
 - [X] Support disabling/skipping hooks when needed (should be made easier)

### Conventions & Rules

 - [X] Add configurable branch naming rules
 - [X] Add configurable tag naming rules
 - [X] Add configurable commit message rules
 - [ ] Add configurable file/path rules
 - [ ] Add configurable commit/push policies
 - [ ] Allow projects to define their own custom rules

### Configuration

 - [X] Add a simple project configuration file
 - [ ] Support per-hook configuration
 - [ ] Support environment variables
 - [X] Support reusable/shared configurations
 - [X] Add configuration validation

### Developer Experience

 - [X] Add an easy initialization command
 - [ ] Add an uninstall/cleanup command
 - [ ] Add a command to check the current configuration
 - [ ] Add helpful CLI output and diagnostics
 - [X] Provide documentation and examples
 - [X] Add easy Git CI/CD integration (almost)
 - [X] Add integration to VS code terminal and auto VS code settings adding in installation scripts

### Distribution

 - [X] Provide prebuilt binaries
 - [X] Support major platforms
 - [X] Provide easy installation methods
 - [X] Automate releases
 - [X] Add CI for builds and tests

---

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/uninstall.sh | sh
```

```powershell
irm https://raw.githubusercontent.com/CM-exe/patou/main/scripts/uninstall.ps1 | iex
```

```cmd
curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/uninstall.cmd -o uninstall.cmd && uninstall.cmd
```
