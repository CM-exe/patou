use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn repo_root() -> io::Result<PathBuf> {
    let output = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()?;

    if !output.status.success() {
        return Err(io::Error::other("not inside a Git repository"));
    }

    let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(PathBuf::from(path))
}

pub fn set_hooks_path(repo_root: &Path, hooks_path: &str) -> io::Result<()> {
    let status = Command::new("git")
        .args(["config", "core.hooksPath", hooks_path])
        .current_dir(repo_root)
        .status()?;

    if !status.success() {
        return Err(io::Error::other("failed to set git core.hooksPath"));
    }
    Ok(())
}
