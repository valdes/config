mod api;
mod cli;
mod daemon;
mod edit;
mod error;
mod lsp;
mod paths;
mod wire;
use serde_json::json;
fn main() {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    if args.first().map(String::as_str) == Some("__serve") {
        let result = args
            .get(1)
            .ok_or_else(|| error::Error::new("usage", "Missing daemon root"))
            .and_then(|r| paths::root(Some(r)))
            .and_then(|r| daemon::serve(&r));
        if let Err(e) = result {
            eprintln!("{e}");
            std::process::exit(1)
        }
        return;
    }
    if args.is_empty() || args.iter().any(|a| a == "--help" || a == "-h") {
        println!("{}", cli::HELP);
        return;
    }
    if args == ["--version"] {
        println!("java-lsp {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    let result = cli::parse(args)
        .and_then(|cli| daemon::call(&cli.root, cli.request).map(|v| (v, cli.human)));
    let (value, human) = match result {
        Ok(v) => v,
        Err(e) => (json!({"ok":false,"error":e.json()}), false),
    };
    if human {
        if let Some(diff) = value["result"]["diff"].as_str() {
            println!(
                "plan {} ({})\n{diff}",
                value["result"]["plan_id"], value["result"]["status"]
            );
        } else {
            println!("{}", serde_json::to_string_pretty(&value).unwrap());
        }
    } else {
        println!("{}", value);
    }
    if value["ok"] != true {
        std::process::exit(if value["error"]["code"] == "usage" {
            2
        } else {
            1
        });
    }
}
