// Native launcher for the "Open Patou bash here" context menu entry
// (registered by `patou init`/the install scripts). Windows-only: it
// uses its own bundled copy of Git for Windows' portable distribution
// (extracted by the install scripts into a `git\` folder next to this
// exe - see scripts/install.ps1 / scripts/install.cmd), writes the
// helper shell script + mintty theme next to itself, and opens an
// ordinary Git Bash session - with Patou's banner, Patou already on
// PATH, and a grey/blue/light-blue mintty theme instead of Git Bash's
// default palette. This makes patou-bash self-contained: it works even
// on a machine with no system-wide Git for Windows install. If the
// bundled copy is somehow missing, it falls back to looking for a
// system install instead of just giving up.
//
// No console of its own (`windows_subsystem = "windows"`): it either
// hands off to mintty or fails silently, logging to patou-bash-error.log
// next to itself so a failure is still diagnosable.
#![windows_subsystem = "windows"]

#[cfg(windows)]
fn main() {
    windows_only::run();
}

#[cfg(not(windows))]
fn main() {
    eprintln!("patou-bash is a Windows-only Git Bash launcher; nothing to do on this platform.");
    std::process::exit(1);
}

#[cfg(windows)]
mod windows_only {
    use std::env;
    use std::fs;
    use std::io;
    use std::path::{Path, PathBuf};
    use std::process::Command;

    const BANNER: &str = include_str!("../../assets/patou-bash-banner.txt");
    const MINTTYRC: &str = include_str!("../../assets/patou-bash.minttyrc");

    pub fn run() {
        if let Err(err) = try_run() {
            log_error(&err.to_string());
        }
    }

    fn try_run() -> io::Result<()> {
        let exe = env::current_exe()?;
        let install_dir = exe
            .parent()
            .ok_or_else(|| io::Error::other("patou-bash.exe has no parent directory"))?;

        let git_install = find_git_install(install_dir).ok_or_else(|| {
            io::Error::other(
                "no usable Git for Windows found: checked the bundled `git\\` \
                 folder next to patou-bash.exe, the registry, common install \
                 locations, and `git`/`where` on PATH",
            )
        })?;

        let mintty = mintty_path(&git_install);

        let shell_script = install_dir.join("patou-shell.sh");
        fs::write(&shell_script, build_shell_script(install_dir))?;

        let minttyrc = install_dir.join("patou-bash.minttyrc");
        fs::write(&minttyrc, MINTTYRC)?;

        // The target folder comes from the context menu's %V/%1
        // substitution (the first argument); falls back to the user's
        // home directory when launched with none (e.g. double-clicked).
        let target_dir = env::args_os()
            .nth(1)
            .map(PathBuf::from)
            .filter(|p| p.is_dir())
            .or_else(|| env::var_os("USERPROFILE").map(PathBuf::from));

        let mut cmd = Command::new(&mintty);
        cmd.arg("-c")
            .arg(&minttyrc)
            .arg("-e")
            .arg("/usr/bin/bash")
            .arg(to_posix_path(&shell_script));
        if let Some(dir) = &target_dir {
            cmd.current_dir(dir);
        }
        cmd.spawn()?;
        Ok(())
    }

    fn build_shell_script(install_dir: &Path) -> String {
        format!(
            "#!/bin/sh\n\
             # Patou bash: an ordinary Git Bash shell with Patou already on PATH.\n\
             # Written by patou-bash.exe on each launch; scripts/uninstall.ps1 and\n\
             # scripts/uninstall.cmd remove it along with patou-bash.exe.\n\
             \n\
             cat <<'PATOU_BANNER'\n{banner}\nPATOU_BANNER\n\
             \n\
             echo\n\
             echo \"Patou -- lightweight, self-contained Git quality tool.\"\n\
             echo \"Run 'patou --help' to get started, or 'patou check' to lint a commit message.\"\n\
             echo\n\
             \n\
             export PATH=\"{bin_dir}:$PATH\"\n\
             exec bash --login -i\n",
            banner = BANNER.trim_end(),
            bin_dir = to_posix_path(install_dir),
        )
    }

    /// "C:\Users\bob\Patou" -> "/c/Users/bob/Patou", for paths passed to
    /// the MSYS bash that Git for Windows ships.
    fn to_posix_path(path: &Path) -> String {
        let slashed = path.to_string_lossy().replace('\\', "/");
        let bytes = slashed.as_bytes();
        if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
            format!("/{}{}", (bytes[0] as char).to_ascii_lowercase(), &slashed[2..])
        } else {
            slashed
        }
    }

    /// Tries several ways to locate a Git for Windows install, roughly in
    /// order of cost. First, and normally the only one that matters: the
    /// private copy the install scripts extract into `git\` next to this
    /// exe, so patou-bash doesn't depend on the system having Git for
    /// Windows installed at all. If that's missing (a broken/partial
    /// install, or patou-bash built and run outside of the installer),
    /// fall back to: the registry key the official installer writes
    /// (absent for e.g. winget/scoop/portable installs), a few common
    /// install directories, then `git --exec-path` / `where git.exe` for
    /// anything else with `git` on PATH. Each candidate is only accepted
    /// once `mintty_path` under it actually exists, since a stale or
    /// unrelated match is as good as no match.
    fn find_git_install(install_dir: &Path) -> Option<PathBuf> {
        let bundled = install_dir.join("git");
        if mintty_path(&bundled).is_file() {
            return Some(bundled);
        }

        for hive in ["HKCU", "HKLM"] {
            if let Some(path) = reg_query_value(hive, r"SOFTWARE\GitForWindows", "InstallPath") {
                let path = PathBuf::from(path);
                if mintty_path(&path).is_file() {
                    return Some(path);
                }
            }
        }

        if let Some(path) = common_install_dirs()
            .into_iter()
            .find(|path| mintty_path(path).is_file())
        {
            return Some(path);
        }

        git_root_from_exec_path().or_else(git_root_from_path_lookup)
    }

    fn mintty_path(git_install: &Path) -> PathBuf {
        git_install.join("usr").join("bin").join("mintty.exe")
    }

    fn common_install_dirs() -> Vec<PathBuf> {
        let mut dirs = Vec::new();
        for var in ["ProgramFiles", "ProgramFiles(x86)"] {
            if let Some(base) = env::var_os(var) {
                dirs.push(PathBuf::from(base).join("Git"));
            }
        }
        if let Some(base) = env::var_os("LocalAppData") {
            dirs.push(PathBuf::from(base).join("Programs").join("Git"));
        }
        dirs
    }

    /// `git --exec-path` prints something like
    /// `C:\Program Files\Git\mingw64\libexec\git-core`; walk up from
    /// there looking for the install root (recognised by `mintty_path`
    /// existing under it).
    fn git_root_from_exec_path() -> Option<PathBuf> {
        let output = Command::new("git").arg("--exec-path").output().ok()?;
        if !output.status.success() {
            return None;
        }
        let exec_path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if exec_path.is_empty() {
            return None;
        }
        find_root_upwards(Path::new(&exec_path))
    }

    /// Falls back to resolving `git.exe` via PATH (`where`) and walking up
    /// from wherever that turns out to be (`cmd\`, `bin\`, or
    /// `mingw64\bin\`, depending on the install).
    fn git_root_from_path_lookup() -> Option<PathBuf> {
        let output = Command::new("where").arg("git.exe").output().ok()?;
        if !output.status.success() {
            return None;
        }
        let first_match = String::from_utf8_lossy(&output.stdout)
            .lines()
            .next()?
            .trim()
            .to_string();
        if first_match.is_empty() {
            return None;
        }
        find_root_upwards(Path::new(&first_match))
    }

    fn find_root_upwards(start: &Path) -> Option<PathBuf> {
        start
            .ancestors()
            .find(|candidate| mintty_path(candidate).is_file())
            .map(Path::to_path_buf)
    }

    /// Shells out to `reg query` rather than adding a registry-access
    /// dependency, consistent with how `src/git.rs` shells out to `git`.
    fn reg_query_value(hive: &str, key: &str, value_name: &str) -> Option<String> {
        let output = Command::new("reg")
            .args(["query", &format!(r"{hive}\{key}"), "/v", value_name])
            .output()
            .ok()?;
        if !output.status.success() {
            return None;
        }

        let text = String::from_utf8_lossy(&output.stdout);
        for line in text.lines() {
            let Some(rest) = line.trim_start().strip_prefix(value_name) else {
                continue;
            };
            let Some(rest) = rest.trim_start().strip_prefix("REG_SZ") else {
                continue;
            };
            let value = rest.trim();
            if !value.is_empty() {
                return Some(value.to_string());
            }
        }
        None
    }

    fn log_error(message: &str) {
        if let Ok(exe) = env::current_exe()
            && let Some(dir) = exe.parent()
        {
            let _ = fs::write(dir.join("patou-bash-error.log"), message);
        }
    }
}
