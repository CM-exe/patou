use std::fs;
use std::io;
use std::io::Write as _;
use std::path::Path;

use crate::git;

const CONFIG_HEADER: &str = r#"# Patou configuration
# Rules defined here are versioned with the repository, so every
# contributor validates commits the same way.

"#;

const COMMIT_CONFIG: &str = r#"[commit]
# Conventional Commits style: type(scope): subject
# Single-quoted (TOML literal string) so the regex needs no escaping and
# the commit-msg hook (plain shell) and `patou check` read the exact same
# bytes.
pattern = '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9-]+\))?: .{1,72}$'
"#;

// Only added when `patou init -b/--branch` is used (or accepted later via
// the "config.toml is missing the [branch] rule" prompt, see `ensure_config`
// below). Same single-quoted-literal-string reasoning as [commit].pattern
// above - this exact pattern is also read by the pre-commit hook's grep -E.
const BRANCH_CONFIG: &str = r#"[branch]
# Branch naming convention, enforced by the pre-commit hook on every commit.
# Defaults: `main`; `develop`/`dev` (drop these two if your workflow has no
# long-lived integration branch); and `<type>/<description>` for
# feature/fix/hotfix/refactor/chore/docs branches.
pattern = '^(main|develop|dev|(feature|fix|hotfix|refactor|chore|docs)/[a-zA-Z0-9._/-]+)$'
"#;

// Only added when `patou init -t/--tag` is used (or accepted later via the
// "config.toml is missing the [tag] rule" prompt). Same
// single-quoted-literal-string reasoning as [commit].pattern above - this
// exact pattern is also read by the pre-push hook's grep -E.
const TAG_CONFIG: &str = r#"[tag]
# Tag naming convention, enforced by the pre-push hook when tags are pushed
# (git has no hook that fires on local tag creation - only pre-push sees
# the refs, tags included, before they leave the machine).
# Defaults: semantic version tags `v<MAJOR>.<MINOR>.<PATCH>` (e.g. v1.4.0),
# and `<type>/<description>` for build/deploy/release tags.
pattern = '^(v[0-9]+\.[0-9]+\.[0-9]+|(build|deploy|release)/[a-zA-Z0-9._/-]+)$'
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

// Only written when `patou init -b/--branch` is used. Self-contained like
// COMMIT_MSG_HOOK, but section-aware when pulling `pattern` out of
// config.toml (unlike the commit-msg hook's plain `grep '^pattern'`) since
// a [branch] section means the file now has two lines starting with
// `pattern`, and the commit-msg hook's naive "first match" approach would
// otherwise silently pick up whichever pattern happens to come first.
const PRE_COMMIT_HOOK: &str = r#"#!/bin/sh
# Patou pre-commit hook. Self-contained: no patou binary required.
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config="$dir/../config.toml"

raw=$(awk '
  /^\[branch\]/ { in_section=1; next }
  /^\[/ { in_section=0 }
  in_section && /^pattern[[:space:]]*=/ { print; exit }
' "$config")
raw=${raw#*=}
raw=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
raw=${raw#\'}
pattern=${raw%\'}

if [ -z "$pattern" ]; then
  exit 0
fi

# Not on a branch (detached HEAD, e.g. mid-rebase) - nothing to validate.
branch=$(git symbolic-ref --short HEAD 2>/dev/null) || exit 0

if printf '%s' "$branch" | grep -Eq "$pattern"; then
  exit 0
fi

echo "branch name rejected: \"$branch\"" >&2
echo "must match pattern: $pattern" >&2
exit 1
"#;

// Only written when `patou init -t/--tag` is used. Self-contained and
// section-aware like PRE_COMMIT_HOOK. Git has no hook for local tag
// creation, so this validates at the one point tags are actually
// observable to a hook: pre-push receives one "<local ref> <local sha>
// <remote ref> <remote sha>" line per stdin per ref being pushed, and a
// pushed tag's local ref is "refs/tags/<name>" - anything else (branches,
// etc.) is left alone.
const PRE_PUSH_HOOK: &str = r#"#!/bin/sh
# Patou pre-push hook. Self-contained: no patou binary required.
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config="$dir/../config.toml"

raw=$(awk '
  /^\[tag\]/ { in_section=1; next }
  /^\[/ { in_section=0 }
  in_section && /^pattern[[:space:]]*=/ { print; exit }
' "$config")
raw=${raw#*=}
raw=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
raw=${raw#\'}
pattern=${raw%\'}

if [ -z "$pattern" ]; then
  exit 0
fi

status=0
while read -r local_ref local_sha remote_ref remote_sha; do
  case "$local_ref" in
    refs/tags/*)
      tag=${local_ref#refs/tags/}
      if ! printf '%s' "$tag" | grep -Eq "$pattern"; then
        echo "tag name rejected: \"$tag\"" >&2
        echo "must match pattern: $pattern" >&2
        status=1
      fi
      ;;
  esac
done

exit $status
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

pub fn run(branch: bool, tag: bool) -> io::Result<()> {
    let repo_root = git::repo_root()?;

    let patou_dir = repo_root.join(".patou");
    let hooks_dir = patou_dir.join("hooks");
    fs::create_dir_all(&hooks_dir)?;
    hide_on_windows(&patou_dir);

    let config_path = patou_dir.join("config.toml");
    let (has_branch, has_tag) = ensure_config(&config_path, branch, tag)?;

    let hook_path = hooks_dir.join("commit-msg");
    write_if_absent(&hook_path, COMMIT_MSG_HOOK)?;
    make_executable(&hook_path)?;

    if has_branch {
        let pre_commit_hook_path = hooks_dir.join("pre-commit");
        write_if_absent(&pre_commit_hook_path, PRE_COMMIT_HOOK)?;
        make_executable(&pre_commit_hook_path)?;
    }

    if has_tag {
        let pre_push_hook_path = hooks_dir.join("pre-push");
        write_if_absent(&pre_push_hook_path, PRE_PUSH_HOOK)?;
        make_executable(&pre_push_hook_path)?;
    }

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
    if has_branch {
        println!("  .patou/hooks/pre-commit (branch naming rule)");
    }
    if has_tag {
        println!("  .patou/hooks/pre-push (tag naming rule)");
    }
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

// Makes sure config.toml has every rule section this invocation wants:
// [commit] unconditionally (it's the baseline rule every `init` has always
// written), [branch] when `want_branch` is true, and [tag] when `want_tag`
// is true. A brand-new file just gets written with everything it needs,
// same as before. An *existing* file is never silently rewritten (`init`
// staying idempotent matters more here than ever, since this file is meant
// to hold hand-edited rules) - instead, for each wanted section missing
// from it, the user is asked whether to append the default block, e.g. so
// a repo that ran plain `init` earlier and now runs `init -b` gets offered
// the [branch] section it's missing rather than silently staying without
// one.
//
// Returns whether [branch] and [tag] each end up present (already there,
// or just added), which is what decides whether the pre-commit/pre-push
// hooks get written below.
fn ensure_config(
    config_path: &Path,
    want_branch: bool,
    want_tag: bool,
) -> io::Result<(bool, bool)> {
    if !config_path.exists() {
        let mut contents = format!("{CONFIG_HEADER}{COMMIT_CONFIG}");
        if want_branch {
            contents.push('\n');
            contents.push_str(BRANCH_CONFIG);
        }
        if want_tag {
            contents.push('\n');
            contents.push_str(TAG_CONFIG);
        }
        fs::write(config_path, contents)?;
        return Ok((want_branch, want_tag));
    }

    println!("  skipped {} (already exists)", config_path.display());
    let existing = fs::read_to_string(config_path)?;
    let mut has_branch = has_section(&existing, "[branch]");
    let mut has_tag = has_section(&existing, "[tag]");

    if !has_section(&existing, "[commit]")
        && prompt_yes_no(
            "  config.toml is missing the [commit] rule - add the default commit message pattern?",
        )
    {
        append_section(config_path, "commit", COMMIT_CONFIG)?;
    }

    if want_branch
        && !has_branch
        && prompt_yes_no(
            "  config.toml is missing the [branch] rule - add the default branch naming pattern?",
        )
    {
        append_section(config_path, "branch", BRANCH_CONFIG)?;
        has_branch = true;
    }

    if want_tag
        && !has_tag
        && prompt_yes_no(
            "  config.toml is missing the [tag] rule - add the default tag naming pattern?",
        )
    {
        append_section(config_path, "tag", TAG_CONFIG)?;
        has_tag = true;
    }

    Ok((has_branch, has_tag))
}

fn has_section(config_contents: &str, marker: &str) -> bool {
    config_contents.lines().any(|line| line.trim() == marker)
}

fn append_section(config_path: &Path, name: &str, block: &str) -> io::Result<()> {
    let mut file = fs::OpenOptions::new().append(true).open(config_path)?;
    write!(file, "\n{block}")?;
    println!("  added [{name}] rule to {}", config_path.display());
    Ok(())
}

// Reads a y/n answer from stdin. Missing/unreadable input (piped-empty
// stdin, EOF) defaults to "no" rather than blocking or assuming consent.
fn prompt_yes_no(question: &str) -> bool {
    print!("{question} [y/N] ");
    let _ = io::stdout().flush();

    let mut answer = String::new();
    if io::stdin().read_line(&mut answer).unwrap_or(0) == 0 {
        return false;
    }
    matches!(answer.trim().to_lowercase().as_str(), "y" | "yes")
}

// A leading "." already keeps `.patou/` out of `ls`/Finder by convention on
// Unix, but Windows has no such convention - a dot-prefixed folder shows up
// in Explorer like any other unless its `FILE_ATTRIBUTE_HIDDEN` attribute is
// set explicitly. Shelling out to `attrib` (built into every Windows
// install) rather than calling `SetFileAttributesW` directly avoids a
// dependency just for this, matching how src/git.rs already shells out to
// `git` instead of linking a Git library - and matches what Git for Windows
// itself does to `.git/` for the same reason. Best-effort: a failure here
// (e.g. `attrib` missing from PATH) doesn't fail `init` over what's purely
// cosmetic, unlike the config/hooks/install-script files above.
#[cfg(windows)]
fn hide_on_windows(path: &Path) {
    let succeeded = std::process::Command::new("attrib")
        .arg("+h")
        .arg(path)
        .status()
        .is_ok_and(|status| status.success());
    if !succeeded {
        println!("note: could not mark {} as hidden", path.display());
    }
}

#[cfg(not(windows))]
fn hide_on_windows(_path: &Path) {}

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
