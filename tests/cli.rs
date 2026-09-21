use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use assert_cmd::Command as AssertCommand;
use predicates::prelude::*;
use tempfile::TempDir;

fn git(dir: &Path, args: &[&str]) -> Output {
    Command::new("git")
        .args(args)
        .current_dir(dir)
        .output()
        .expect("failed to run git")
}

fn init_git_repo() -> TempDir {
    let dir = TempDir::new().expect("failed to create temp dir");
    let status = git(dir.path(), &["init", "-q"]).status;
    assert!(status.success(), "git init failed");
    git(dir.path(), &["config", "user.email", "test@example.com"]);
    git(dir.path(), &["config", "user.name", "Test"]);
    git(dir.path(), &["config", "commit.gpgsign", "false"]);
    dir
}

fn patou(dir: &Path) -> AssertCommand {
    let mut cmd = AssertCommand::cargo_bin("patou").expect("patou binary not found");
    cmd.current_dir(dir);
    cmd
}

fn write_message(dir: &Path, name: &str, content: &str) -> PathBuf {
    let path = dir.join(name);
    fs::write(&path, content).expect("failed to write message file");
    path
}

fn hooks_path(dir: &Path) -> String {
    String::from_utf8_lossy(&git(dir, &["config", "core.hooksPath"]).stdout)
        .trim()
        .to_string()
}

#[test]
fn running_with_no_subcommand_prints_help_and_succeeds() {
    let repo = init_git_repo();

    patou(repo.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("Usage: patou"))
        .stdout(predicate::str::contains("init"))
        .stdout(predicate::str::contains("install"))
        .stdout(predicate::str::contains("check"));
}

#[test]
fn init_creates_config_hooks_and_install_scripts() {
    let repo = init_git_repo();

    patou(repo.path()).arg("init").assert().success();

    for path in [
        ".patou/config.toml",
        ".patou/hooks/commit-msg",
        ".patou/install",
        ".patou/install.cmd",
        ".patou/install.ps1",
    ] {
        assert!(repo.path().join(path).is_file(), "missing {path}");
    }

    assert_eq!(hooks_path(repo.path()), ".patou/hooks");
}

#[test]
fn init_is_idempotent() {
    let repo = init_git_repo();

    patou(repo.path()).arg("init").assert().success();
    patou(repo.path())
        .arg("init")
        .assert()
        .success()
        .stdout(predicate::str::contains("already exists"));
}

#[test]
fn check_accepts_conventional_commit_message() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    let msg = write_message(repo.path(), "msg.txt", "feat(cli): add check command\n");

    patou(repo.path())
        .arg("check")
        .arg(&msg)
        .assert()
        .success()
        .stdout(predicate::str::contains("commit message OK"));
}

#[test]
fn check_rejects_non_conventional_commit_message() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    let msg = write_message(repo.path(), "msg.txt", "added stuff\n");

    patou(repo.path())
        .arg("check")
        .arg(&msg)
        .assert()
        .failure()
        .stderr(predicate::str::contains("commit message rejected"));
}

#[test]
fn check_ignores_comment_and_blank_lines_before_the_subject() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    let msg = write_message(
        repo.path(),
        "msg.txt",
        "\n# comment from git\nfeat(cli): add check command\n",
    );

    patou(repo.path())
        .arg("check")
        .arg(&msg)
        .assert()
        .success()
        .stdout(predicate::str::contains("commit message OK"));
}

#[test]
fn check_raw_accepts_a_single_quoted_argument() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    patou(repo.path())
        .args(["check", "-r", "feat(cli): add raw option"])
        .assert()
        .success()
        .stdout(predicate::str::contains("commit message OK"));
}

#[test]
fn check_raw_joins_unquoted_words_into_one_message() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    patou(repo.path())
        .args(["check", "--raw", "feat:", "add", "raw", "option"])
        .assert()
        .success()
        .stdout(predicate::str::contains("commit message OK"));
}

#[test]
fn check_raw_rejects_non_conventional_commit_message() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    patou(repo.path())
        .args(["check", "-r", "added stuff"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("commit message rejected"));
}

#[test]
fn check_rejects_message_file_and_raw_together() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    let msg = write_message(repo.path(), "msg.txt", "feat(cli): add raw option\n");

    patou(repo.path())
        .arg("check")
        .arg(&msg)
        .args(["-r", "feat(cli): add raw option"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("cannot be used with"));
}

#[test]
fn check_without_message_file_skips_the_commit_rule() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    patou(repo.path())
        .arg("check")
        .assert()
        .success()
        .stdout(predicate::str::contains("skipping"));
}

#[test]
fn check_fails_when_not_initialized() {
    let repo = init_git_repo();

    patou(repo.path())
        .arg("check")
        .assert()
        .failure()
        .stderr(predicate::str::contains("patou init"));
}

#[test]
fn check_fails_with_invalid_toml_config() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    fs::write(repo.path().join(".patou/config.toml"), "not valid toml {{{").unwrap();
    let msg = write_message(repo.path(), "msg.txt", "feat: ok\n");

    patou(repo.path())
        .arg("check")
        .arg(&msg)
        .assert()
        .failure()
        .stderr(predicate::str::contains("invalid .patou/config.toml"));
}

#[test]
fn check_fails_with_invalid_regex_pattern() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    fs::write(
        repo.path().join(".patou/config.toml"),
        "[commit]\npattern = '('\n",
    )
    .unwrap();
    let msg = write_message(repo.path(), "msg.txt", "feat: ok\n");

    patou(repo.path())
        .arg("check")
        .arg(&msg)
        .assert()
        .failure()
        .stderr(predicate::str::contains("invalid commit.pattern regex"));
}

#[test]
fn install_relinks_hooks_path_after_it_was_cleared() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    git(repo.path(), &["config", "--unset", "core.hooksPath"]);
    assert_eq!(hooks_path(repo.path()), "");

    patou(repo.path()).arg("install").assert().success();

    assert_eq!(hooks_path(repo.path()), ".patou/hooks");
}

#[test]
fn install_fails_when_not_initialized() {
    let repo = init_git_repo();

    patou(repo.path())
        .arg("install")
        .assert()
        .failure()
        .stderr(predicate::str::contains("patou init"));
}

/// End-to-end: the compiled `patou` binary's directory is never added to
/// PATH in this test, and the hook is invoked by `git commit` itself (not
/// by us calling `patou` directly). This proves the commit-msg hook
/// installed by `init` is genuinely self-contained shell, with no
/// dependency on a globally installed `patou`.
#[test]
fn commit_msg_hook_enforces_rules_without_a_global_patou_install() {
    let repo = init_git_repo();
    patou(repo.path()).arg("init").assert().success();

    fs::write(repo.path().join("file.txt"), "hello\n").unwrap();
    git(repo.path(), &["add", "file.txt"]);

    let bad = git(repo.path(), &["commit", "-m", "not conventional"]);
    assert!(
        !bad.status.success(),
        "expected the non-conventional commit to be rejected by the hook"
    );

    let good = git(repo.path(), &["commit", "-m", "feat: add file"]);
    assert!(
        good.status.success(),
        "expected the conventional commit to succeed: {}",
        String::from_utf8_lossy(&good.stderr)
    );

    let log = git(repo.path(), &["log", "--oneline"]);
    assert_eq!(
        String::from_utf8_lossy(&log.stdout).lines().count(),
        1,
        "only the conventional commit should have gone through"
    );
}
