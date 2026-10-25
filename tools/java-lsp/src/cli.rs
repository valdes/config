use crate::{
    error::{Error, Result},
    paths,
};
use serde_json::{Value, json};
use std::{collections::BTreeMap, io::Read, path::PathBuf};
pub const HELP: &str = r#"java-lsp [--root PATH] COMMAND [OPTIONS]

Lifecycle: start | status | stop | restart | refresh | capabilities
Query: symbols [--query TEXT | --file PATH]
       definition | references | implementations | hover --file PATH --at LINE:COLUMN
       hierarchy --kind callers|callees|supertypes|subtypes --file PATH --at LINE:COLUMN
       diagnostics --file PATH
       actions --file PATH --at LINE:COLUMN [--end LINE:COLUMN]
Refactor: refactor OP --file PATH [--at LINE:COLUMN] [--end LINE:COLUMN]
          [--name NAME] [--describe] [--spec FILE|-] [--action TITLE]
          OP: rename, imports, extract-method, extract-variable, extract-constant,
              extract-interface, inline, change-signature, move, quickfix
Plans: plan show|apply|recover PLAN_ID

Options: --human, --timeout SECONDS (60), --init-timeout SECONDS (300), --limit N (200)
Positions: one-based lines and Unicode scalar columns; range end is exclusive.
Refactors produce previews. Only plan apply/recover write project files.
"#;
pub struct Cli {
    pub root: PathBuf,
    pub request: Value,
    pub human: bool,
}
pub fn parse(args: Vec<String>) -> Result<Cli> {
    let mut flags = BTreeMap::new();
    let mut words = vec![];
    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        if let Some(key) = arg.strip_prefix("--") {
            if ![
                "root",
                "file",
                "at",
                "end",
                "name",
                "query",
                "kind",
                "spec",
                "action",
                "timeout",
                "init-timeout",
                "limit",
                "human",
                "describe",
            ]
            .contains(&key)
            {
                return Err(Error::new("usage", format!("Unknown option: {arg}")));
            }
            let value = if matches!(key, "human" | "describe") {
                json!(true)
            } else {
                i += 1;
                json!(
                    args.get(i)
                        .ok_or_else(|| Error::new("usage", format!("Missing value for {arg}")))?
                )
            };
            if flags.insert(key.to_owned(), value).is_some() {
                return Err(Error::new("usage", format!("Duplicate option {arg}")));
            }
        } else {
            words.push(arg.clone());
        }
        i += 1;
    }
    let command = words
        .first()
        .ok_or_else(|| Error::new("usage", HELP))?
        .as_str();
    let expected = match command {
        "plan" => 3,
        "refactor" => 2,
        "start" | "status" | "stop" | "restart" | "refresh" | "capabilities" | "symbols"
        | "definition" | "references" | "implementations" | "hover" | "hierarchy"
        | "diagnostics" | "actions" => 1,
        _ => return Err(Error::new("usage", format!("Unknown command {command}"))),
    };
    if words.len() != expected {
        return Err(Error::new(
            "usage",
            "Unexpected or missing positional arguments",
        ));
    }
    let needs_position = matches!(
        command,
        "definition" | "references" | "implementations" | "hover" | "hierarchy" | "actions"
    ) || (command == "refactor"
        && !matches!(words[1].as_str(), "imports" | "move"));
    if needs_position && !flags.contains_key("at") {
        return Err(Error::new(
            "usage",
            "This command requires --at LINE:COLUMN",
        ));
    }
    let root = paths::root(flags.get("root").and_then(Value::as_str))?;
    let human = flags.get("human") == Some(&json!(true));
    let mut request = json!({"command":command,"options":flags});
    if command == "refactor" {
        request["operation"] = json!(words[1]);
    }
    if command == "plan" {
        if !["show", "apply", "recover"].contains(&words[1].as_str()) {
            return Err(Error::new("usage", "Expected plan show|apply|recover"));
        }
        request["operation"] = json!(words[1]);
        request["plan_id"] = json!(words[2]);
    }
    for (key, default, max) in [
        ("timeout", 60, 3600),
        ("init-timeout", 300, 3600),
        ("limit", 200, 10000),
    ] {
        let number = match flags.get(key) {
            Some(v) => v
                .as_str()
                .unwrap()
                .parse::<u64>()
                .map_err(|_| Error::new("usage", format!("Invalid {key}")))?,
            None => default,
        };
        if number == 0 || number > max {
            return Err(Error::new("usage", format!("{key} must be 1..{max}")));
        }
        request["options"][key] = json!(number);
    }
    if let Some(path) = flags.get("spec").and_then(Value::as_str) {
        let mut bytes = vec![];
        if path == "-" {
            std::io::stdin()
                .take(1024 * 1024 + 1)
                .read_to_end(&mut bytes)?;
        } else {
            std::fs::File::open(path)?
                .take(1024 * 1024 + 1)
                .read_to_end(&mut bytes)?;
        }
        if bytes.len() > 1024 * 1024 {
            return Err(Error::new("too_large", "Specification exceeds 1 MiB"));
        }
        request["spec"] = serde_json::from_slice(&bytes)?;
    }
    Ok(Cli {
        root,
        request,
        human,
    })
}
