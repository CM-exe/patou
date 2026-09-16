# Getting started

## 1. Scaffold Patou into a repository

From inside a Git repository, with `patou` installed (see
[Installation](./installation.md)):

```bash
patou init
```

This creates:

```
.patou/
├── config.toml       # rules, versioned with the project
├── hooks/
│   └── commit-msg     # the actual Git hook, pure POSIX shell
├── install            # activation script for Linux/macOS/Git Bash
├── install.cmd         # activation script for Windows cmd.exe
└── install.ps1         # activation script for Windows PowerShell
```

and immediately activates the hooks for the repository you ran it in
(`git config core.hooksPath .patou/hooks`).

## 2. Commit `.patou/`

```bash
git add .patou
git commit -m "chore: set up patou"
```

Everything a contributor needs — the rules and the hook that enforces
them — now travels with the repository.

## 3. Contributors just clone and activate

Anyone who clones the repository activates the hooks with a single
command, and it does **not** require `patou` to be installed:

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

From then on, every `git commit` is validated automatically by the
`commit-msg` hook.

## 4. Try it

```bash
git commit -m "not a conventional message"
# rejected

git commit -m "feat: add the widget"
# accepted
```

## Checking a message manually

If you have `patou` installed, you can validate any message file directly
— useful for scripting or debugging a rule:

```bash
echo "feat: my change" > msg.txt
patou check msg.txt
```
