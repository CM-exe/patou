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
    use std::os::windows::process::CommandExt;
    use std::path::{Path, PathBuf};
    use std::process::Command;

    const BANNER: &str = include_str!("../../assets/patou-bash-banner.txt");

    // Passed to every Command that shells out to a *console* program (reg,
    // git, where) from this process. patou-bash.exe is windows_subsystem =
    // "windows" (no console of its own): without this flag, spawning a
    // console-subsystem child can make Windows attach or briefly allocate a
    // console for it, which is how a launch that's supposed to be silent
    // (this runs on every "Open Patou bash here" and on install/
    // --customize-only) ends up leaking a child's OS-locale error text
    // (e.g. a failed `git --exec-path`/`where git.exe` lookup) into
    // whatever console happens to be around - a cmd.exe window running
    // install.cmd, for instance - instead of staying invisible like the
    // rest of this launcher. `.output()` already pipes stdout/stderr so
    // nothing is lost - this only controls console *allocation*.
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

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
#
# Reasserted via PROMPT_COMMAND rather than a plain one-shot `PS1=...`
# here: on standalone MSYS2 (unlike Git for Windows, which sets its
# default PS1 directly in /etc/profile, before profile.d runs), the
# default interactive PS1 is set later, in ~/.bashrc/etc/bash.bashrc -
# sourced by bash's login-shell init *after* /etc/profile.d, which would
# silently clobber a plain assignment made here. Re-applying PS1 from
# PROMPT_COMMAND, which every prompt draw invokes last, wins regardless
# of that ordering.

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

# Keeps the standalone mintty window's title as "Patou Bash - <cwd>",
# updated on every prompt draw so it tracks wherever you've since cd'd to
# - mintty starts with a plain "Patou Bash" title (see the `-t` argument
# in launch_branded_mintty in this same source file), which this then
# immediately overrides. Only for that standalone window, not the VS Code
# integrated-terminal profile (see Add-VsCodeTerminalProfile in
# scripts/install.ps1): mintty sets TERM_PROGRAM=mintty automatically,
# distinguishing it from VS Code's own TERM_PROGRAM=vscode, whose terminal
# tab title VS Code itself already owns.
__patou_set_title() {
    [ "$TERM_PROGRAM" = "mintty" ] || return
    printf '\033]0;Patou Bash - %s\007' "$PWD"
}

__patou_set_prompt() {
    __patou_set_title
    PS1='\[\033[32m\]\u@\h \[\033[35m\]\w\[\033[0m\]'"$(__patou_git_branch)"'\n\$ '
}

case ";$PROMPT_COMMAND;" in
    *";__patou_set_prompt;"*) ;;
    *) PROMPT_COMMAND="__patou_set_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
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

        let first_arg = env::args_os().nth(1);

        // A hidden flag scripts/install.ps1 and scripts/install.cmd run
        // once, right after installing, rather than waiting for someone
        // to use "Open Patou bash here" for the first time: it writes the
        // same profile.d banner/prompt scripts customize_bundled_git
        // always (re)writes before launching a real session below - most
        // importantly the PATH export in banner_script, which is what
        // puts `patou` itself on PATH inside any bundled-bash session.
        // Without this, that only ever happened on this launcher's own
        // first run - fine for the mintty-based context menu entry, but
        // VS Code's integrated-terminal profile (see
        // Add-VsCodeTerminalProfile in scripts/install.ps1) runs
        // bash.exe directly and never goes through this launcher at all,
        // so `patou` would stay missing from its PATH until someone
        // separately used "Open Patou bash here" at least once. No
        // console or window is shown either way (windows_subsystem =
        // "windows"), so this is safe to invoke unattended from an
        // install script.
        if first_arg.as_deref() == Some(std::ffi::OsStr::new("--customize-only")) {
            let bundled = install_dir.join("msys64");
            if mintty_exe(&bundled).is_file() {
                customize_bundled_git(&bundled, install_dir)?;
            }
            return Ok(());
        }

        // The target folder comes from the context menu's %V/%1
        // substitution (the first argument).
        let target_dir = first_arg.map(PathBuf::from).filter(|p| p.is_dir());

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
        // git-bash.exe explicitly sets HOME to the Windows user profile
        // before it ever gets to bash - it's not a MINGW64-vs-MSYS thing
        // (MSYSTEM only picks which subsystem's bin/ goes on PATH). Left
        // unset, this bundled MSYS2's own HOME resolution can land
        // somewhere else entirely (e.g. a fabricated /home/<user> under
        // this private msys64\, which may not even exist yet) instead of
        // the same folder Explorer/git-bash/Windows itself call "home",
        // so `~` wouldn't match. Setting it here, the same way
        // git-bash.exe does, keeps the two consistent.
        if let Some(home) = windows_home_dir() {
            cmd.env("HOME", to_posix_path(&home));
        }
        if let Some(dir) = target_dir {
            cmd.current_dir(dir);
            // /etc/profile unconditionally `cd`s a login shell to $HOME
            // unless this is set - the same guard `git-bash.exe`'s own
            // `--cd` flag sets internally before invoking mintty. Without
            // it, `Command::current_dir` above only sets mintty's own
            // starting directory; bash's login init then immediately cds
            // away from it back to $HOME.
            cmd.env("CHERE_INVOKING", "1");
        }
        cmd.spawn()?;
        Ok(())
    }

    /// The Windows user profile directory (`C:\Users\bob`), i.e. what
    /// git-bash.exe itself uses as `HOME` - `USERPROFILE`, falling back
    /// to `HOMEDRIVE`+`HOMEPATH` for the rare environment missing it.
    fn windows_home_dir() -> Option<PathBuf> {
        if let Some(profile) = env::var_os("USERPROFILE") {
            return Some(PathBuf::from(profile));
        }
        let mut combined = env::var_os("HOMEDRIVE")?;
        combined.push(env::var_os("HOMEPATH")?);
        Some(PathBuf::from(combined))
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
        fs::write(profile_d.join("patou-git-bridge.sh"), git_bridge_script())?;
        ensure_vi_alias(git_root)?;

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

    /// Bridges this private bundled git to a *system* Git for Windows
    /// install's own system-level config, if one is found (the same
    /// search `find_system_git_install` does for the no-bundled-copy
    /// fallback, reused here for a bundled copy that's very much
    /// present) - written as another `/etc/profile.d` script so it
    /// applies to every login shell in this bundled MSYS2 the same way
    /// patou-banner.sh/patou-prompt.sh do, which covers both the
    /// standalone mintty window (launch_branded_mintty) and the VS Code
    /// integrated-terminal profile (Add-VsCodeTerminalProfile in
    /// scripts/install.ps1) without either needing its own copy of this
    /// logic - both ultimately run `bash --login`, which sources
    /// /etc/profile -> /etc/profile.d.
    ///
    /// *System*-level config - most importantly `credential.helper`
    /// (GitHub/GitLab/etc. sign-in), which the Git for Windows
    /// installer/Git Credential Manager setup writes into that install's
    /// own `etc/gitconfig` - doesn't carry over to this bundled copy's
    /// separate one on its own. `GIT_CONFIG_SYSTEM` (Git >= 2.32, long
    /// since true for both Git for Windows and MSYS2's git package)
    /// points this bundled git at that file directly instead of
    /// duplicating its contents. The credential helper it names (e.g.
    /// `manager`) is a bare executable name git resolves via PATH -
    /// `git-credential-manager(.exe)` lives under that system install's
    /// `mingw64\bin\` or `cmd\`, neither of which is otherwise on this
    /// bundled session's PATH, hence adding both here too.
    ///
    /// *Global* config (`user.name`/`user.email`, etc.) needs the same
    /// treatment, for a reason that's easy to get wrong: it is NOT
    /// enough to just point this bundled session's `HOME` at the
    /// Windows user profile (see launch_branded_mintty) and assume that
    /// resolves to the same `~/.gitconfig` a system Git for Windows
    /// reads - on some machines (e.g. a domain-joined profile where
    /// `HOMEDRIVE`/`HOMEPATH` diverges from `USERPROFILE`) it doesn't,
    /// and this bundled git then silently starts from a blank global
    /// config instead. Rather than reverse-engineer whichever HOME
    /// variable a real Git for Windows install actually resolves to,
    /// `system_global_gitconfig` just asks its own `git.exe` directly
    /// (`config --global --list --show-origin`) and bridges that exact
    /// file via `GIT_CONFIG_GLOBAL`, sidestepping the question entirely.
    fn git_bridge_script() -> String {
        let Some(system_root) = find_system_git_install() else {
            return "# No system Git for Windows install found - nothing to bridge.\n".to_string();
        };

        let global_config_export = match system_global_gitconfig(&system_root) {
            Some(path) => format!("export GIT_CONFIG_GLOBAL='{}'\n", to_posix_path(&path)),
            None => String::new(),
        };

        format!(
            "# Patou bash git config bridge - sourced automatically by every\n\
             # login shell in this bundled MSYS2 install via /etc/profile.\n\
             # Written by patou-bash.exe on each launch; scripts/uninstall.ps1\n\
             # and scripts/uninstall.cmd remove the whole bundled msys64\\ folder.\n\
             #\n\
             # Bridges this private git install to the system Git for Windows\n\
             # install found at {system_root_display} - see the git_bridge_script\n\
             # doc comment in patou-bash's own source for why.\n\
             \n\
             export GIT_CONFIG_SYSTEM='{system_config}'\n\
             {global_config_export}export PATH=\"{bin1}:{bin2}:$PATH\"\n",
            system_root_display = system_root.display(),
            system_config = to_posix_path(&system_gitconfig(&system_root)),
            bin1 = to_posix_path(&system_root.join("mingw64").join("bin")),
            bin2 = to_posix_path(&system_root.join("cmd")),
        )
    }

    /// The system-level config file a system Git for Windows install's
    /// own `git config --system` edits - where its installer/Git
    /// Credential Manager setup writes `credential.helper`, distinct
    /// from this project's own bundled copy's separate `etc/gitconfig`
    /// (which patou never writes to).
    fn system_gitconfig(system_root: &Path) -> PathBuf {
        system_root.join("etc").join("gitconfig")
    }

    /// Where the bundled MSYS2's `vim` package (installed by
    /// msys2-bundle.yml) puts its binary - used both to decide whether
    /// `ensure_vi_alias` has anything to point at (an older bundle
    /// predating that package addition won't have it) and as the actual
    /// target of the `vi` wrapper it writes.
    fn vim_exe(git_root: &Path) -> PathBuf {
        git_root.join("usr").join("bin").join("vim.exe")
    }

    /// Writes a plain `vi` -> `vim` wrapper into this bundle (`exec vim
    /// "$@"`) - standalone MSYS2's `git` package ships no editor at all,
    /// so without this, anything that invokes `vi` by name (git's own
    /// hardcoded editor fallback included, once nothing else is
    /// configured) fails outright: "error: cannot spawn vi: No such file
    /// or directory". Written the same unremarkable way
    /// `.patou/hooks/commit-msg` already is elsewhere in this project
    /// (`fs::write`, no chmod/exec-bit handling) - MSYS treats a
    /// shebang'd file as invocable regardless of any Windows-level
    /// "executable" attribute, the same thing that already makes that
    /// hook work with no chmod call on Windows. Skipped if `vim.exe`
    /// isn't in this bundle, and never overwrites a `vi` that already
    /// exists (e.g. a future bundle that ships a real one).
    fn ensure_vi_alias(git_root: &Path) -> io::Result<()> {
        if !vim_exe(git_root).is_file() {
            return Ok(());
        }
        let vi_path = git_root.join("usr").join("bin").join("vi");
        if vi_path.is_file() {
            return Ok(());
        }
        fs::write(vi_path, "#!/bin/sh\nexec vim \"$@\"\n")
    }

    /// One of a system Git for Windows install's own `git.exe` binaries
    /// (there are several - `cmd\git.exe` and `bin\git.exe` are thin
    /// shims, `mingw64\bin\git.exe` is the real one - any of them
    /// resolves config identically) - used to ask it directly where its
    /// global config lives, rather than assuming this bundled copy's own
    /// `HOME`-based resolution lands on the same file.
    fn system_git_exe(system_root: &Path) -> Option<PathBuf> {
        [
            system_root.join("cmd").join("git.exe"),
            system_root.join("bin").join("git.exe"),
            system_root.join("mingw64").join("bin").join("git.exe"),
        ]
        .into_iter()
        .find(|candidate| candidate.is_file())
    }

    /// Runs a system Git for Windows install's own `git.exe` and reads
    /// back exactly which file it resolved its global config to
    /// (`--show-origin` prints a `file:<path>` prefix on each line) -
    /// see the reasoning in `git_bridge_script`'s doc comment for why
    /// this asks git itself instead of recomputing the path. `None` if
    /// no `git.exe` was found, the command failed, it printed nothing
    /// (no global config set at all), or the file it named doesn't
    /// actually exist.
    fn system_global_gitconfig(system_root: &Path) -> Option<PathBuf> {
        let git_exe = system_git_exe(system_root)?;
        let output = Command::new(git_exe)
            .args(["config", "--global", "--list", "--show-origin"])
            .creation_flags(CREATE_NO_WINDOW)
            .output()
            .ok()?;
        let stdout = String::from_utf8_lossy(&output.stdout);
        let origin = stdout.lines().next()?.split('\t').next()?;
        let path = PathBuf::from(origin.strip_prefix("file:")?);
        path.is_file().then_some(path)
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
        let output = Command::new("git")
            .arg("--exec-path")
            .creation_flags(CREATE_NO_WINDOW)
            .output()
            .ok()?;
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
        let output = Command::new("where")
            .arg("git.exe")
            .creation_flags(CREATE_NO_WINDOW)
            .output()
            .ok()?;
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
            .creation_flags(CREATE_NO_WINDOW)
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
