//! rulelab: command line interface. M0 has the VM commands only.

use clap::{Parser, Subcommand};
use rulelab_vm::Program;
use std::process::ExitCode;

mod docs;

#[derive(Parser)]
#[command(name = "rulelab", about = "Search for local learning rules")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Assemble a program and print its canonical number
    Asm { src: String },
    /// Print the assembly of a rule number
    Disasm { number: String },
    /// Print the register map and op table
    Ops,
    /// Regenerate docs/ops.md from the op table
    Docs {
        #[arg(long, default_value = "docs/ops.md")]
        out: String,
    },
}

fn main() -> ExitCode {
    match run(Cli::parse().cmd) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run(cmd: Cmd) -> Result<(), Box<dyn std::error::Error>> {
    match cmd {
        Cmd::Asm { src } => {
            let p = Program::assemble(&src)?;
            println!("{}", p.number());
            println!("{}", p.canonical().disassemble());
        }
        Cmd::Disasm { number } => {
            let p = Program::parse_number(&number)?;
            let canonical = p.number();
            if canonical != number.trim() {
                println!("# canonical number: {canonical}");
            }
            println!("{}", p.disassemble());
        }
        Cmd::Ops => print!("{}", docs::ops_markdown()),
        Cmd::Docs { out } => {
            std::fs::write(&out, docs::ops_markdown())?;
            println!("wrote {out}");
        }
    }
    Ok(())
}
