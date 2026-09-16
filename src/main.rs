use clap::{CommandFactory, Parser, Subcommand};
use std::path::PathBuf;
use std::process::ExitCode;

mod commands;
mod git;

#[derive(Parser)]
#[command(name = "patou", version, about = "Lightweight, self-contained Git quality tool", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize Patou in a Git repository (config + hooks)
    Init,
    /// Activate Patou for an existing repository (link the githooks)
    Install,
    /// Validate a commit against the project's rules
    Check {
        /// Path to the commit message file, as passed by the commit-msg hook
        message_file: Option<PathBuf>,
    },
}

fn main() -> ExitCode {
    let cli = Cli::parse();

    let Some(command) = cli.command else {
        Cli::command().print_help().expect("failed to print help");
        println!();
        return ExitCode::SUCCESS;
    };

    let result = match command {
        Commands::Init => commands::init::run().map(|_| true),
        Commands::Install => commands::install::run(),
        Commands::Check { message_file } => commands::check::run(message_file),
    };

    match result {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(err) => {
            eprintln!("error: {err}");
            ExitCode::FAILURE
        }
    }
}
