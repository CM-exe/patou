use std::fs;
use std::io;
use std::path::Path;

use crate::git;

const DEFAULT_CONFIG: &str = r#"# Patou configuration
# Rules defined here are versioned with the repository, so every
# contributor validates commits the same way.

[commit]
# Conventional Commits style: type(scope): subject
# Single-quoted (TOML literal string) so the regex needs no escaping and
# the commit-msg hook (plain shell) and `patou check` read the exact same
# bytes.
pattern = '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9-]+\))?: .{1,72}$'
"#;

// Fully self-contained: reads the pattern straight out of config.toml and
// validates with grep. No patou binary required, so a repository that has
// run `init` works for any contributor who just clones it and runs
// `.patou/install`.
const COMMIT_MSG_HOOK: &str = r#"#!/bin/sh
# Patou commit-msg hook. Self-contained: no patou binary required.
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config="$dir/../config.toml"
msg_file="$1"

raw=$(grep '^pattern' "$config" | head -n1)
raw=${raw#*=}
raw=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
raw=${raw#\'}
pattern=${raw%\'}

if [ -z "$pattern" ]; then
  exit 0
fi

subject=$(grep -v '^#' "$msg_file" | grep -v '^[[:space:]]*$' | head -n1)

if printf '%s' "$subject" | grep -Eq "$pattern"; then
  echo "commit message OK"
  exit 0
fi

echo "commit message rejected: \"$subject\"" >&2
echo "must match pattern: $pattern" >&2
exit 1
"#;

// Activates the hooks for one clone (sets the per-clone core.hooksPath git
// config, which `git clone` never carries over). Plain shell so it works
// with no patou binary at all — this is the one thing a contributor who
// only cloned the repository needs to run.
const INSTALL_SCRIPT: &str = r#"#!/bin/sh
# Activates Patou for this clone. No patou binary required.
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$dir/.." && pwd)

if [ ! -d "$dir/hooks" ]; then
  echo "no $dir/hooks found - is Patou set up in this repository?" >&2
  exit 1
fi

git -C "$repo_root" config core.hooksPath .patou/hooks
echo "Patou activated for $repo_root"
echo "  git config core.hooksPath -> .patou/hooks"
"#;

// Windows native wrapper (cmd.exe). The commit-msg hook itself already runs
// fine on Windows because Git for Windows executes hook shebang scripts
// through its bundled sh — but a user typing directly in cmd.exe can't run
// `.patou/install` (no shebang support), hence this equivalent.
const INSTALL_CMD: &str = "@echo off\r\nsetlocal\r\nset \"dir=%~dp0\"\r\nif not exist \"%dir%hooks\" (\r\n  echo no %dir%hooks found - is Patou set up in this repository? 1>&2\r\n  exit /b 1\r\n)\r\nfor %%I in (\"%dir%..\") do set \"repo_root=%%~fI\"\r\ngit -C \"%repo_root%\" config core.hooksPath .patou/hooks\r\nif errorlevel 1 exit /b 1\r\necho Patou activated for %repo_root%\r\necho   git config core.hooksPath -^> .patou/hooks\r\nendlocal\r\n";

// Windows native wrapper (PowerShell), same purpose as INSTALL_CMD.
const INSTALL_PS1: &str = "$ErrorActionPreference = 'Stop'\r\n$dir = Split-Path -Parent $MyInvocation.MyCommand.Path\r\n$repoRoot = Split-Path -Parent $dir\r\n\r\nif (-not (Test-Path (Join-Path $dir 'hooks'))) {\r\n    Write-Error \"no $dir\\hooks found - is Patou set up in this repository?\"\r\n    exit 1\r\n}\r\n\r\ngit -C $repoRoot config core.hooksPath .patou/hooks\r\nif ($LASTEXITCODE -ne 0) { exit 1 }\r\n\r\nWrite-Host \"Patou activated for $repoRoot\"\r\nWrite-Host \"  git config core.hooksPath -> .patou/hooks\"\r\n";

pub fn run() -> io::Result<()> {
    let repo_root = git::repo_root()?;

    let patou_dir = repo_root.join(".patou");
    let hooks_dir = patou_dir.join("hooks");
    fs::create_dir_all(&hooks_dir)?;

    let config_path = patou_dir.join("config.toml");
    write_if_absent(&config_path, DEFAULT_CONFIG)?;

    let hook_path = hooks_dir.join("commit-msg");
    write_if_absent(&hook_path, COMMIT_MSG_HOOK)?;
    make_executable(&hook_path)?;

    let install_path = patou_dir.join("install");
    write_if_absent(&install_path, INSTALL_SCRIPT)?;
    make_executable(&install_path)?;

    let install_cmd_path = patou_dir.join("install.cmd");
    write_if_absent(&install_cmd_path, INSTALL_CMD)?;

    let install_ps1_path = patou_dir.join("install.ps1");
    write_if_absent(&install_ps1_path, INSTALL_PS1)?;

    git::set_hooks_path(&repo_root, ".patou/hooks")?;

    println!("Initialized Patou in {}", repo_root.display());
    println!("  .patou/config.toml");
    println!("  .patou/hooks/commit-msg");
    println!("  .patou/install (Linux/macOS/Git Bash)");
    println!("  .patou/install.cmd (Windows cmd.exe)");
    println!("  .patou/install.ps1 (Windows PowerShell)");
    println!("  git config core.hooksPath -> .patou/hooks");
    println!();
    println!("Commit `.patou/` so contributors who clone the repository only");
    println!("need to run `.patou/install` (or the .cmd/.ps1 variant on");
    println!("Windows) to activate the rules — no global patou install");
    println!("required.");

    Ok(())
}

fn write_if_absent(path: &Path, contents: &str) -> io::Result<()> {
    if path.exists() {
        println!("  skipped {} (already exists)", path.display());
        return Ok(());
    }
    fs::write(path, contents)
}

#[cfg(unix)]
fn make_executable(path: &Path) -> io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mut perms = fs::metadata(path)?.permissions();
    perms.set_mode(perms.mode() | 0o111);
    fs::set_permissions(path, perms)
}

#[cfg(not(unix))]
fn make_executable(_path: &Path) -> io::Result<()> {
    Ok(())
}
