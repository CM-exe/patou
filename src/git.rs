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
    // `-C repo_root` rather than `Command::current_dir(repo_root)`: repo_root
    // is exactly the string `git rev-parse --show-toplevel` printed, and on
    // Windows that's not guaranteed to be a path the OS's own CreateProcess
    // can chdir into (e.g. a network-mapped home directory can come back in
    // a form Win32 rejects as a process's current directory, even though
    // it's fine for git and for Rust's own std::fs calls). Handing the same
    // string straight back to git via `-C` lets git resolve its own output
    // itself instead of asking the OS to.
    let status = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["config", "core.hooksPath", hooks_path])
        .status()?;

    if !status.success() {
        return Err(io::Error::other("failed to set git core.hooksPath"));
    }
    Ok(())
}
