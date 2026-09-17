// Native launcher for the "Open Patou bash here" context menu entry
// (registered by `patou init`/the install scripts). Windows-only.
//
// For its own bundled standalone MSYS2 install (extracted + bootstrapped
// by the install scripts into a `msys64\` folder next to this exe - see
// scripts/install.ps1 / scripts/install.cmd), this launches
// `usr\bin\mintty.exe` directly with the exact recipe Git for Windows'
// own `git-bash.exe` uses (extracted from its embedded command-line
// resource: `--nodaemon -o AppID=... -o AppLaunchCmd=... -o AppName=...
// -i <exe> --store-taskbar-properties -- /usr/bin/bash --login -i`),
// substituting Patou's own icon/name - `git-bash.exe` can't be reused
// as-is for this, since it hardcodes `-i <itself>`, always showing Git's
// icon regardless of what launched it. `patou-bash.exe` itself is the
// icon source (`-i`): it already carries `assets/favicon.ico` as its own
// PE resource (see `build.rs`), and mintty's `-i FILE` accepts any
// executable with an icon resource, not just `.ico` files.
//
// If that bundled copy is somehow missing, this falls back to a system
// Git for Windows install instead of just giving up - there, it reuses
// `git-bash.exe` as-is (`--cd=<dir>`, same as the official installer's
// own "Git Bash Here" shortcut), deliberately NOT rebranding it: it's
// the user's own copy, shared with their everyday Git Bash use.
//
// Patou's banner and mintty color theme are layered on through Git for
// Windows' own customization points, applied only to its own bundled
// copy: an `etc/profile.d/*.sh` script (sourced automatically by every
// login shell) and `etc/minttyrc` (mintty's default config file) - see
// `customize_bundled_git`.
//
// No console of its own (`windows_subsystem = "windows"`): it either
// hands off to mintty/git-bash.exe or fails silently, logging to
// patou-bash-error.log next to itself so a failure is still diagnosable.
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
    use std::ffi::OsString;
    use std::fs;
    use std::io;
    use std::path::{Path, PathBuf};
    use std::process::Command;

    const BANNER: &str = include_str!("../../assets/patou-bash-banner.txt");

    // Overrides PS1 to show the current branch next to the path, like Git
    // Bash's own default prompt (`__git_ps1`) - white for a plain repo,
    // or light blue (matching assets/patou-bash.minttyrc's BoldCyan) when
    // the repo also has a `.patou/` directory. `__patou_git_branch` is
    // self-contained rather than depending on git-prompt.sh (which
    // standalone MSYS2's `git` package, unlike Git for Windows, doesn't
    // ship): it shells out to `git` directly and prints nothing outside a
    // repo, so PS1 is unaffected when not in one.
    const PROMPT_SCRIPT: &str = r#"# Patou bash prompt - sourced automatically by every login shell in
# this bundled MSYS2 install via /etc/profile. Written by patou-bash.exe
# on each launch; scripts/uninstall.ps1 and scripts/uninstall.cmd remove
# the whole bundled msys64\ folder.

__patou_git_branch() {
    local branch
    branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=$(git rev-parse --short HEAD 2>/dev/null) || return
    local toplevel
    toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
    local color=37 # white
    if [ -n "$toplevel" ] && [ -d "$toplevel/.patou" ]; then
        color=36 # light blue - this repo also has .patou
    fi
    printf ' \033[1;%sm(%s)\033[0m' "$color" "$branch"
}

PS1='\[\033[32m\]\u@\h \[\033[35m\]\w\[\033[0m\]$(__patou_git_branch)\n\$ '
"#;

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

        // The target folder comes from the context menu's %V/%1
        // substitution (the first argument).
        let target_dir = env::args_os().nth(1).map(PathBuf::from).filter(|p| p.is_dir());

        let bundled = install_dir.join("msys64");
        if mintty_exe(&bundled).is_file() {
            customize_bundled_git(&bundled, install_dir)?;
            return launch_branded_mintty(&bundled, &exe, target_dir.as_deref());
        }

        // No branding here: this is the *user's* system Git for Windows
        // install, shared with their own everyday Git Bash use, not
        // patou's private copy - reuse its own git-bash.exe unmodified
        // rather than showing Patou's icon on somebody else's shell.
        let system_root = find_system_git_install().ok_or_else(|| {
            io::Error::other(
                "no usable Git Bash found: checked the bundled `msys64\\` \
                 folder next to patou-bash.exe, the registry, common install \
                 locations, and `git`/`where` on PATH",
            )
        })?;
        launch_system_git_bash(&system_root, target_dir.as_deref())
    }

    fn mintty_exe(git_root: &Path) -> PathBuf {
        git_root.join("usr").join("bin").join("mintty.exe")
    }

    fn git_bash_exe(git_root: &Path) -> PathBuf {
        git_root.join("git-bash.exe")
    }

    /// Launches patou's bundled mintty directly, mirroring `git-bash.exe`'s
    /// own proven invocation (see the module docs) but with Patou's own
    /// icon/name: `own_exe` (this running patou-bash.exe, already carrying
    /// `assets/favicon.ico` as its PE icon resource) is what mintty's `-i`
    /// extracts the window/taskbar icon from.
    fn launch_branded_mintty(git_root: &Path, own_exe: &Path, target_dir: Option<&Path>) -> io::Result<()> {
        let mut cmd = Command::new(mintty_exe(git_root));
        cmd.arg("--nodaemon")
            .arg("-o")
            .arg("AppID=Patou.Bash")
            .arg("-o")
            .arg(app_launch_cmd_option(own_exe))
            .arg("-o")
            .arg("AppName=Patou Bash")
            .arg("-i")
            .arg(own_exe)
            .arg("--store-taskbar-properties")
            .arg("-t")
            .arg("Patou Bash")
            .arg("--")
            .arg("/usr/bin/bash")
            .arg("--login")
            .arg("-i");
        if let Some(dir) = target_dir {
            cmd.current_dir(dir);
        }
        cmd.spawn()?;
        Ok(())
    }

    fn app_launch_cmd_option(own_exe: &Path) -> OsString {
        let mut opt = OsString::from("AppLaunchCmd=");
        opt.push(own_exe);
        opt
    }

    /// Reuses a system Git for Windows install's own launcher as-is - it
    /// already knows how to find its own mintty, icon, and environment.
    fn launch_system_git_bash(git_root: &Path, target_dir: Option<&Path>) -> io::Result<()> {
        let mut cmd = Command::new(git_bash_exe(git_root));
        if let Some(dir) = target_dir {
            let mut arg = OsString::from("--cd=");
            arg.push(dir);
            cmd.arg(arg);
        }
        cmd.spawn()?;
        Ok(())
    }

    /// Writes Patou's banner (as an `/etc/profile.d` script, sourced by
    /// every login shell automatically) and mintty color theme (as
    /// `etc/minttyrc`, mintty's own default config file) into patou's
    /// private bundled MSYS2 install. Safe to call on every launch -
    /// both are small, idempotent overwrites, so they can't drift out of
    /// sync with the compiled banner/theme.
    fn customize_bundled_git(git_root: &Path, install_dir: &Path) -> io::Result<()> {
        let profile_d = git_root.join("etc").join("profile.d");
        fs::create_dir_all(&profile_d)?;
        fs::write(profile_d.join("patou-banner.sh"), banner_script(install_dir))?;
        fs::write(profile_d.join("patou-prompt.sh"), PROMPT_SCRIPT)?;

        fs::write(
            git_root.join("etc").join("minttyrc"),
            concat!(
                "Columns=100\n",
                "Rows=27\n",
                "Term=xterm-256color\n",
                include_str!("../../assets/patou-bash.minttyrc"),
            ),
        )?;
        Ok(())
    }

    fn banner_script(install_dir: &Path) -> String {
        format!(
            "# Patou bash banner - sourced automatically by every login shell\n\
             # in this bundled MSYS2 install via /etc/profile. Written by\n\
             # patou-bash.exe on each launch; scripts/uninstall.ps1 and\n\
             # scripts/uninstall.cmd remove the whole bundled msys64\\ folder.\n\
             \n\
             cat <<'PATOU_BANNER'\n{banner}\nPATOU_BANNER\n\
             \n\
             echo\n\
             echo \"Patou -- lightweight, self-contained Git quality tool.\"\n\
             echo \"Run 'patou --help' to get started, or 'patou check' to lint a commit message.\"\n\
             echo\n\
             \n\
             export PATH=\"{bin_dir}:$PATH\"\n",
            banner = BANNER.trim_end(),
            bin_dir = to_posix_path(install_dir),
        )
    }

    /// "C:\Users\bob\Patou" -> "/c/Users/bob/Patou", for the PATH entry
    /// exported into the MSYS bash that Git for Windows ships.
    fn to_posix_path(path: &Path) -> String {
        let slashed = path.to_string_lossy().replace('\\', "/");
        let bytes = slashed.as_bytes();
        if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
            format!("/{}{}", (bytes[0] as char).to_ascii_lowercase(), &slashed[2..])
        } else {
            slashed
        }
    }

    /// Tries several ways to locate a *system* Git for Windows install,
    /// for when patou's own bundled copy is missing (a broken/partial
    /// install, or patou-bash built and run outside of the installer):
    /// the registry key the official installer writes (absent for e.g.
    /// winget/scoop/portable installs), a few common install
    /// directories, then `git --exec-path` / `where git.exe` for
    /// anything else with `git` on PATH. Each candidate is only accepted
    /// once `git-bash.exe` under it actually exists, since a stale or
    /// unrelated match is as good as no match.
    fn find_system_git_install() -> Option<PathBuf> {
        for hive in ["HKCU", "HKLM"] {
            if let Some(path) = reg_query_value(hive, r"SOFTWARE\GitForWindows", "InstallPath") {
                let path = PathBuf::from(path);
                if git_bash_exe(&path).is_file() {
                    return Some(path);
                }
            }
        }

        if let Some(path) = common_install_dirs()
            .into_iter()
            .find(|path| git_bash_exe(path).is_file())
        {
            return Some(path);
        }

        git_root_from_exec_path().or_else(git_root_from_path_lookup)
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
    /// there looking for the install root (recognised by `git-bash.exe`
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
            .find(|candidate| git_bash_exe(candidate).is_file())
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
