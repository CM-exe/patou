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
patou check
```
