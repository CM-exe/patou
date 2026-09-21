use std::fs;
use std::io;
use std::path::PathBuf;

use regex::Regex;
use serde::Deserialize;

use crate::git;

#[derive(Deserialize, Default)]
struct Config {
    commit: Option<CommitRule>,
}

#[derive(Deserialize)]
struct CommitRule {
    pattern: String,
}

/// Runs the configured checks. Returns `Ok(true)` when everything passes,
/// `Ok(false)` when a rule is violated, and `Err` for unexpected failures
/// (missing config, invalid TOML, I/O errors...).
pub fn run(message_file: Option<PathBuf>, raw: Option<Vec<String>>) -> io::Result<bool> {
    let repo_root = git::repo_root()?;
    let config_path = repo_root.join(".patou").join("config.toml");

    let config_text = fs::read_to_string(&config_path).map_err(|_| {
        io::Error::other(format!(
            "no Patou config found at {} — run `patou init` first",
            config_path.display()
        ))
    })?;

    let config: Config = toml::from_str(&config_text)
        .map_err(|err| io::Error::other(format!("invalid .patou/config.toml: {err}")))?;

    let Some(commit_rule) = config.commit else {
        println!("no [commit] rule configured, nothing to check");
        return Ok(true);
    };

    // clap already rejects passing both (see `conflicts_with` on
    // `message_file`) - joined with plain spaces since that's exactly how
    // an unquoted `patou check -r feat: add x` arrives (one word per arg,
    // shell-quoting already resolved), and a single already-quoted arg
    // just passes through unchanged.
    let message = match (message_file, raw) {
        (Some(path), None) => Some(fs::read_to_string(&path)?),
        (None, Some(words)) => Some(words.join(" ")),
        (None, None) => None,
        (Some(_), Some(_)) => unreachable!("clap rejects --raw together with a message file"),
    };

    check_commit_message(&commit_rule, message)
}

fn check_commit_message(rule: &CommitRule, message: Option<String>) -> io::Result<bool> {
    let regex = Regex::new(&rule.pattern)
        .map_err(|err| io::Error::other(format!("invalid commit.pattern regex: {err}")))?;

    let Some(message) = message else {
        println!("no commit message provided, skipping [commit] rule");
        println!(
            "hint: `patou check` is meant to run from the commit-msg hook installed by `patou init`, or pass a message file / -r/--raw \"<message>\""
        );
        return Ok(true);
    };

    let subject = message
        .lines()
        .find(|line| !line.trim().is_empty() && !line.trim_start().starts_with('#'))
        .unwrap_or("")
        .trim();

    if regex.is_match(subject) {
        println!("commit message OK");
        Ok(true)
    } else {
        eprintln!("commit message rejected: \"{subject}\"");
        eprintln!("must match pattern: {}", rule.pattern);
        Ok(false)
    }
}
