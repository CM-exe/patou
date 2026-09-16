<div align="center">

<img src="assets/logo-patou.png" alt="Patou logo" width="420">

# Patou

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

## 🗺️ Roadmap

### Git Hooks

 - [ ] Support common Git hooks (pre-commit, commit-msg, pre-push, etc.)
 - [X] Make hook installation simple and reliable
 - [ ] Support custom hook scripts
 - [ ] Support multiple commands per hook
 - [X] Provide clear error messages and exit codes
 - [X] Support disabling/skipping hooks when needed (should be made easier)

### Conventions & Rules

 - [ ] Add configurable branch naming rules
 - [ ] Add configurable tag naming rules
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
 - [ ] Add easy Git CI/CD integration (almost)

### Distribution

 - [X] Provide prebuilt binaries
 - [X] Support major platforms
 - [X] Provide easy installation methods
 - [X] Automate releases
 - [X] Add CI for builds and tests
