use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;

use crate::git;

const DEFAULT_CONFIG: &str = r#"# Patou configuration
# Rules defined here are versioned with the repository, so every
# contributor validates commits the same way.

[commit]
# Conventional Commits style: type(scope): subject
pattern = "^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\\([a-z0-9-]+\\))?: .{1,72}$"
"#;

const COMMIT_MSG_HOOK: &str = "#!/bin/sh\npatou check \"$1\"\n";

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

    set_hooks_path(&repo_root)?;

    println!("Initialized Patou in {}", repo_root.display());
    println!("  .patou/config.toml");
    println!("  .patou/hooks/commit-msg");
    println!("  git config core.hooksPath -> .patou/hooks");

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

fn set_hooks_path(repo_root: &Path) -> io::Result<()> {
    let status = Command::new("git")
        .args(["config", "core.hooksPath", ".patou/hooks"])
        .current_dir(repo_root)
        .status()?;

    if !status.success() {
        return Err(io::Error::other("failed to set git core.hooksPath"));
    }
    Ok(())
}
