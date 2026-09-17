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
    Ok(PathBuf::from(native_path(path)))
}

// Git for Windows patches its git.exe to always print native Windows paths
// (`C:/Users/...`) from commands like `rev-parse --show-toplevel`, precisely
// so non-MSYS-aware tools like `patou.exe` can use the result as-is. A
// vanilla/standalone MSYS2 `git` (patou-bash's own bundled copy, or any
// other plain MSYS2 install on PATH) has no such patch and prints a genuine
// MSYS/Cygwin-style POSIX path instead (`/c/Users/...`). Left unconverted,
// that string still "looks like" a path to `std::fs`/`Path`, but Windows has
// no concept of an MSYS drive mount: a leading `/` with no drive letter
// resolves as "root of the current drive", so `/c/Users/bob/repo` quietly
// becomes `<current drive>:\c\Users\bob\repo` - a different, usually-absent
// location - rather than failing loudly. Every `patou` command that shells
// out to `git` and then touches the filesystem depends on this conversion
// having already happened.
#[cfg(windows)]
fn native_path(path: String) -> String {
    let bytes = path.as_bytes();
    let is_msys_path = bytes.len() >= 2 && bytes[0] == b'/' && bytes[1].is_ascii_alphabetic() && (bytes.len() == 2 || bytes[2] == b'/');
    if !is_msys_path {
        return path;
    }
    let drive = (bytes[1] as char).to_ascii_uppercase();
    let rest = if bytes.len() == 2 { "/" } else { &path[2..] };
    format!("{drive}:{rest}")
}

#[cfg(not(windows))]
fn native_path(path: String) -> String {
    path
}

pub fn set_hooks_path(repo_root: &Path, hooks_path: &str) -> io::Result<()> {
    // `-C repo_root` rather than `Command::current_dir(repo_root)`: even
    // after `native_path` above, letting git resolve its own repo root
    // itself (which it always can) is more robust than asking the OS to
    // `chdir` a new process into a path patou only reconstructed secondhand.
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
