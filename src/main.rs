use clap::{Parser, Subcommand};
use std::process::ExitCode;

mod commands;

#[derive(Parser)]
#[command(name = "patou", version, about = "Lightweight, self-contained Git quality tool", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize Patou in a Git repository (config + hooks)
    Init,
    /// Activate Patou for an existing repository (link the githooks)
    Install,
    /// Validate staged changes against the project's rules
    Check,
}

fn main() -> ExitCode {
    let cli = Cli::parse();

    let result = match cli.command {
        Commands::Init => commands::init::run(),
        Commands::Install => {
            println!("patou install");
            Ok(())
        }
        Commands::Check => {
            println!("patou check");
            Ok(())
        }
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("error: {err}");
            ExitCode::FAILURE
        }
    }
}
