use std::io;

use crate::git;

/// Activates Patou for a repository that was already set up with `patou
/// init` (config and hooks are already tracked in `.patou/`). All this does
/// is point Git's `core.hooksPath` at them — a per-clone setting that isn't
/// carried over by `git clone`.
///
/// Contributors who only cloned the repository don't need the `patou`
/// binary for this: `.patou/install` is a plain shell script that does the
/// same thing and ships with the repository.
pub fn run() -> io::Result<bool> {
    let repo_root = git::repo_root()?;
    let hooks_dir = repo_root.join(".patou").join("hooks");

    if !hooks_dir.is_dir() {
        eprintln!(
            "no .patou/hooks found in {} — run `patou init` first",
            repo_root.display()
        );
        return Ok(false);
    }

    git::set_hooks_path(&repo_root, ".patou/hooks")?;

    println!("Patou activated for {}", repo_root.display());
    println!("  git config core.hooksPath -> .patou/hooks");

    Ok(true)
}
