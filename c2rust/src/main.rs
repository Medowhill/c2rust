use clap::{crate_authors, load_yaml, App, AppSettings, SubCommand};
use git_testament::{git_testament, render_testament};
use std::env;
use std::ffi::OsStr;
use std::process::{exit, Command};

git_testament!(TESTAMENT);

fn main() {
    let subcommand_yamls = [load_yaml!("transpile.yaml"), load_yaml!("instrument.yaml")];
    let matches = App::new("C2Rust")
        .version(&*render_testament!(TESTAMENT))
        .author(crate_authors!(", "))
        .setting(AppSettings::SubcommandRequiredElseHelp)
        .subcommands(
            subcommand_yamls
                .iter()
                .map(|yaml| SubCommand::from_yaml(yaml)),
        )
        .get_matches();

    let mut os_args = env::args_os();
    os_args.next(); // Skip executable name
    let arg_name = os_args.next().and_then(|name| name.into_string().ok());
    match (&arg_name, matches.subcommand_name()) {
        (Some(arg_name), Some(subcommand)) if arg_name == subcommand => {
            invoke_subcommand(subcommand, os_args);
        }
        _ => {
            eprintln!("{:?}", arg_name);
            panic!("Could not match subcommand");
        }
    };
}

fn invoke_subcommand<I, S>(subcommand: &str, args: I)
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    // Assumes the subcommand executable is in the same directory as this driver
    // program.
    let cmd_path = std::env::current_exe().expect("Cannot get current executable path");
    let mut cmd_path = cmd_path.as_path().canonicalize().unwrap();
    cmd_path.pop(); // remove current executable
    cmd_path.push(format!("c2rust-{}", subcommand));
    assert!(cmd_path.exists(), "{:?} is missing", cmd_path);
    exit(
        Command::new(cmd_path.into_os_string())
            .args(args)
            .status()
            .expect("SubCommand failed to start")
            .code()
            .unwrap_or(-1),
    );
}
