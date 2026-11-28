#![cfg_attr(
    all(target_os = "windows", not(feature = "console"), not(debug_assertions)),
    windows_subsystem = "windows"
)]

mod config;
mod error;
mod plugins;
mod protocol;

use std::process::ExitCode;

use crate::config::Config;
use crate::error::Error;
use crate::plugins::Plugins;
use crate::protocol::Protocol;

fn main() -> ExitCode {
    match run() {
        Ok(_) => ExitCode::SUCCESS,
        Err(e) => print_error(e),
    }
}

/// Run handler
fn run() -> Result<(), Error> {
    let args: Vec<String> = std::env::args().collect();
    #[cfg(target_os = "macos")]
    if let [program] = args.as_slice()
        && std::path::Path::new(program).ends_with("mpv-handler-debug")
        && let Ok(url) = std::env::var("MPV_HANDLER_URL")
        && url.starts_with("mpv-handler-debug://")
    {
        use std::io::{IsTerminal, Write};
        use std::os::unix::process::CommandExt;

        let mut stdout = std::io::stdout().lock();
        if stdout.is_terminal() {
            stdout.write_all(b"\x1b[2J\x1b[3J\x1b[H")?;
            stdout.flush()?;
        }

        // Terminal opens the executable as a document, without arguments.
        let error = std::process::Command::new(std::env::current_exe()?)
            .arg(url)
            .env(
                "PATH",
                std::env::var_os("MPV_HANDLER_PATH").unwrap_or_default(),
            )
            .env(
                "XDG_CONFIG_HOME",
                std::env::var_os("MPV_HANDLER_XDG").unwrap_or_default(),
            )
            .env_remove("MPV_HANDLER_URL")
            .env_remove("MPV_HANDLER_PATH")
            .env_remove("MPV_HANDLER_XDG")
            .exec();
        return Err(error.into());
    }

    let arg: &str = match args.len() {
        2 => &args[1],
        1 => return Ok(print_usage()),
        _ => return Err(Error::TooManyArgs),
    };

    let proto = Protocol::parse(arg)?;
    let config = Config::load()?;

    // Call plugin by scheme
    match proto.plugin {
        Plugins::Play => crate::plugins::play::exec(&proto, &config),
    }
}

/// Print usage
fn print_usage() {
    let version: &str = option_env!("MPV_HANDLER_VERSION").unwrap_or(env!("CARGO_PKG_VERSION"));

    println!("mpv-handler {}\n", version);
    println!("Usage:\n  {}\n", "mpv-handler <url>",);
}

/// Print error
fn print_error(e: Error) -> ExitCode {
    eprint!("{e}");
    std::io::Read::read(&mut std::io::stdin(), &mut []).unwrap();

    match e {
        Error::PlayerExited(code) => ExitCode::from(code),
        _ => ExitCode::FAILURE,
    }
}
