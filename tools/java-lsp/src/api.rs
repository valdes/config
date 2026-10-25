use crate::{
    edit,
    error::{Error, Result, required},
    lsp::Lsp,
    paths,
};
use serde_json::{Value, json};
use std::{fs, path::Path};
fn option<'a>(r: &'a Value, key: &str) -> Option<&'a str> {
    r["options"][key].as_str()
}
fn file(lsp: &mut Lsp, r: &Value) -> Result<(String, String)> {
    let path = paths::checked(
        &lsp.root,
        Path::new(option(r, "file").ok_or_else(|| Error::new("usage", "--file is required"))?),
    )?;
    let text = fs::read_to_string(&path)?;
    if text.len() > 8 * 1024 * 1024 {
        return Err(Error::new("too_large", "File exceeds 8 MiB"));
    }
    let uri = lsp.open_text(&path, &text)?;
    // JDT's Java extension requests do not join document lifecycle jobs.
    // documentSymbol does, so its response is a barrier after didOpen/didChange.
    lsp.request(
        "textDocument/documentSymbol",
        json!({"textDocument": {"uri": uri}}),
    )?;
    Ok((uri, text))
}
fn context(lsp: &mut Lsp, r: &Value) -> Result<Value> {
    let (uri, text) = file(lsp, r)?;
    let at = edit::position(&text, option(r, "at").unwrap_or("1:1"))?;
    let end = edit::position(
        &text,
        option(r, "end").unwrap_or(option(r, "at").unwrap_or("1:1")),
    )?;
    if edit::offset(&text, &end)? < edit::offset(&text, &at)? {
        return Err(Error::new("position", "Range end precedes start"));
    }
    Ok(
        json!({"textDocument":{"uri":uri},"position":at,"range":{"start":at,"end":end},"context":{"diagnostics":lsp.diagnostics.get(&uri).map(|v|v["diagnostics"].clone()).unwrap_or(json!([]))}}),
    )
}
fn nonempty(value: Value) -> Result<Value> {
    if value.is_null() {
        Err(Error::new(
            "unavailable",
            "Operation is not available at this location",
        ))
    } else if let Some(e) = value["errorMessage"].as_str() {
        if e.is_empty() {
            Ok(value)
        } else {
            Err(Error::new("refactoring_conflict", e).detail(value))
        }
    } else {
        Ok(value)
    }
}
fn actions(lsp: &mut Lsp, ctx: &Value) -> Result<Value> {
    lsp.request("textDocument/codeAction", ctx.clone())
}
pub fn run(lsp: &mut Lsp, state: &Path, r: &Value) -> Result<Value> {
    let command = required(r, "command")?;
    lsp.timeout = std::time::Duration::from_secs(r["options"]["timeout"].as_u64().unwrap_or(60));
    if command == "capabilities" {
        return Ok(
            json!({"standard":lsp.capabilities,"server":lsp.server_info,"tested_jdtls":"1.60.0","refactorings":["rename","imports","extract-method","extract-variable","extract-constant","extract-interface","inline (available code actions)","change-signature","move","quickfix (edit-only code actions)"],"unsupported":["pull-up","push-down","extract-superclass"],"note":"Availability and semantic preconditions are checked at the selected location"}),
        );
    }
    lsp.sync()?;
    if command == "refresh" {
        return Ok(json!({"generation":lsp.generation,"status":lsp.status}));
    }
    if command == "symbols" {
        return if let Some(query) = option(r, "query") {
            lsp.request("workspace/symbol", json!({"query":query}))
        } else {
            let (uri, _) = file(lsp, r)?;
            lsp.request(
                "textDocument/documentSymbol",
                json!({"textDocument":{"uri":uri}}),
            )
        };
    }
    if command == "diagnostics" {
        let (uri, _) = file(lsp, r)?;
        return lsp.diagnostic(&uri);
    }
    let ctx = context(lsp, r)?;
    let params = json!({"textDocument":ctx["textDocument"],"position":ctx["position"]});
    match command {
        "definition" => lsp.request("textDocument/definition", params),
        "references" => lsp.request(
            "textDocument/references",
            json!({
                "textDocument": ctx["textDocument"], "position": ctx["position"],
                "context": {"includeDeclaration": true}
            }),
        ),
        "implementations" => lsp.request("textDocument/implementation", params),
        "hover" => lsp.request("textDocument/hover", params),
        "actions" => actions(lsp, &ctx),
        "hierarchy" => {
            let kind =
                option(r, "kind").ok_or_else(|| Error::new("usage", "--kind is required"))?;
            let (prepare, method) = match kind {
                "callers" => (
                    "textDocument/prepareCallHierarchy",
                    "callHierarchy/incomingCalls",
                ),
                "callees" => (
                    "textDocument/prepareCallHierarchy",
                    "callHierarchy/outgoingCalls",
                ),
                "supertypes" => (
                    "textDocument/prepareTypeHierarchy",
                    "typeHierarchy/supertypes",
                ),
                "subtypes" => (
                    "textDocument/prepareTypeHierarchy",
                    "typeHierarchy/subtypes",
                ),
                _ => return Err(Error::new("usage", "Unknown hierarchy kind")),
            };
            let items = lsp.request(prepare, params)?;
            let array = items
                .as_array()
                .ok_or_else(|| Error::new("unavailable", "No hierarchy at location"))?;
            if array.len() != 1 {
                return Err(Error::new("ambiguous", "Expected one hierarchy target").detail(items));
            }
            lsp.request(method, json!({"item": array[0]}))
        }
        "refactor" => refactor(lsp, state, r, ctx),
        _ => Err(Error::new("usage", "Unknown semantic command")),
    }
}
fn refactor(lsp: &mut Lsp, state: &Path, r: &Value, ctx: Value) -> Result<Value> {
    if let Some(id) = edit::pending(state)? {
        return Err(Error::new(
            "recovery_required",
            format!("Run plan recover {id}"),
        ));
    }
    let op = required(r, "operation")?;
    if op != "rename"
        && op != "inline"
        && op != "quickfix"
        && !lsp.server_info["version"]
            .as_str()
            .is_some_and(|v| v == "1.60.0" || v.starts_with("1.60.0-"))
    {
        return Err(Error::new("incompatible_server", "JDT-specific adapters require the tested 1.60.0 protocol; standard LSP operations remain available").detail(lsp.server_info.clone()));
    }
    let fingerprint = lsp.generation;
    let describe = r["options"]["describe"] == true;
    let spec = &r["spec"];
    let mut response = match op {
        "rename" => {
            let name =
                option(r, "name").ok_or_else(|| Error::new("usage", "Rename requires --name"))?;
            lsp.request(
                "textDocument/prepareRename",
                json!({"textDocument":ctx["textDocument"],"position":ctx["position"]}),
            )
            .and_then(nonempty)?;
            lsp.request("textDocument/rename",json!({"textDocument":ctx["textDocument"],"position":ctx["position"],"newName":name}))?
        }
        "imports" => lsp.request("java/organizeImports", ctx.clone())?,
        "extract-method" | "extract-variable" | "extract-constant" => {
            let command = match op {
                "extract-method" => "extractMethod",
                "extract-variable" => "extractVariable",
                _ => "extractConstant",
            };
            lsp.request("java/getRefactorEdit",json!({"command":command,"context":ctx,"options":{"tabSize":4,"insertSpaces":true}}))?
        }
        "change-signature" => {
            let info = nonempty(lsp.request("java/getChangeSignatureInfo", ctx.clone())?)?;
            if describe {
                return Ok(info);
            }
            if !spec.is_object() {
                return Err(Error::new(
                    "choices_required",
                    "Use --describe, then supply --spec with methodName, modifier, returnType, parameters, exceptions, delegate",
                ));
            }
            let args = json!([
                info["methodIdentifier"],
                spec["delegate"].as_bool().unwrap_or(false),
                spec.get("methodName").unwrap_or(&info["methodName"]),
                spec.get("modifier").unwrap_or(&info["modifier"]),
                spec.get("returnType").unwrap_or(&info["returnType"]),
                spec.get("parameters").unwrap_or(&info["parameters"]),
                spec.get("exceptions").unwrap_or(&info["exceptions"]),
                false
            ]);
            lsp.request(
                "java/getRefactorEdit",
                json!({"command":"changeSignature","context":ctx,"commandArguments":args}),
            )?
        }
        "extract-interface" => {
            let info = nonempty(lsp.request("java/checkExtractInterfaceStatus", ctx.clone())?)?;
            if describe {
                return Ok(info);
            }
            if !spec["members"].is_array() || !spec["destination"].is_object() {
                return Err(Error::new(
                    "choices_required",
                    "Use --describe; --spec needs members (handle identifiers), name, destination",
                ));
            }
            let name = required(spec, "name")?;
            lsp.request("java/getRefactorEdit",json!({"command":"extractInterface","context":ctx,"commandArguments":[spec["members"],name,spec["destination"]]}))?
        }
        "move" => {
            let kind = spec["kind"].as_str().unwrap_or("moveResource");
            if ![
                "moveResource",
                "moveInstanceMethod",
                "moveStaticMember",
                "moveTypeToNewFile",
            ]
            .contains(&kind)
            {
                return Err(Error::new("unsupported", "Unknown move kind"));
            }
            let p = json!({"moveKind":kind,"sourceUris":[ctx["textDocument"]["uri"]],"params":ctx,"destination":spec["destination"],"updateReferences":true});
            if describe {
                return nonempty(lsp.request("java/getMoveDestinations", p)?);
            }
            if spec["destination"].is_null() && kind != "moveTypeToNewFile" {
                return Err(Error::new(
                    "choices_required",
                    "Use --describe, then --spec with kind and destination",
                ));
            }
            lsp.request("java/move", p)?
        }
        "inline" | "quickfix" => {
            let mut list = actions(lsp, &ctx)?.as_array().cloned().unwrap_or_default();
            list.retain(|a| {
                a["kind"].as_str().is_some_and(|k| {
                    k.starts_with(if op == "inline" {
                        "refactor.inline"
                    } else {
                        "quickfix"
                    })
                })
            });
            if describe {
                return Ok(json!(list));
            }
            let title = option(r, "action");
            let matches = list
                .iter()
                .filter(|a| title.is_none_or(|t| a["title"] == t))
                .cloned()
                .collect::<Vec<_>>();
            if matches.len() != 1 {
                return Err(Error::new(
                    "choices_required",
                    "Choose an available action with --action TITLE",
                )
                .detail(json!(list)));
            }
            let mut a = matches[0].clone();
            if a.get("disabled").is_some() {
                return Err(Error::new("unavailable", "Code action is disabled").detail(a));
            }
            if a.get("edit").is_none() && a.get("data").is_some() {
                a = lsp.request("codeAction/resolve", a)?;
            }
            if a.get("command").is_some() {
                return Err(Error::new("unsupported","This code action requires a client command; use a dedicated refactoring adapter").detail(a));
            }
            nonempty(a["edit"].clone())?
        }
        _ => {
            return Err(Error::new(
                "unsupported",
                format!("No JDT LS adapter for {op}"),
            ));
        }
    };
    response = nonempty(response)?;
    let mut edit_value = if response.get("edit").is_some() {
        nonempty(response["edit"].clone())?
    } else {
        response.clone()
    };
    if let Some(command) = response.get("command").filter(|v| !v.is_null()) {
        if command["command"] != "java.action.rename" {
            return Err(
                Error::new("unsupported", "Unknown refactoring follow-up command")
                    .detail(command.clone()),
            );
        }
        if let Some(name) = option(r, "name") {
            edit_value = rename_overlay(lsp, &edit_value, command, name)?;
        }
    } else if option(r, "name").is_some() && op.starts_with("extract-") && op != "extract-interface"
    {
        return Err(Error::new(
            "unsupported",
            "Server did not supply a linked name for extraction",
        ));
    }
    lsp.verify_snapshot()?;
    if lsp.generation != fingerprint {
        return Err(Error::new(
            "stale_analysis",
            "Workspace changed during refactoring",
        ));
    }
    if let Some(changes) = edit_value["documentChanges"].as_array() {
        for change in changes {
            if let Some(version) = change["textDocument"]["version"].as_i64() {
                let uri = required(&change["textDocument"], "uri")?;
                if lsp.documents.get(uri).map(|d| d.1) != Some(version) {
                    return Err(Error::new(
                        "stale_analysis",
                        "Server edit has an outdated document version",
                    ));
                }
            }
        }
    }
    edit::save(state, &lsp.root, op, &edit_value)
}
fn rename_overlay(lsp: &mut Lsp, first: &Value, command: &Value, name: &str) -> Result<Value> {
    let files = edit::materialize(&lsp.root, first)?;
    let f = files.as_object().unwrap();
    if f.len() != 1 {
        return Err(Error::new(
            "unsupported",
            "Linked-name extraction must edit one existing file",
        ));
    }
    let (key, value) = f.iter().next().unwrap();
    let before = required(&value["before"], "text")?;
    let after = required(&value["after"], "text")?;
    let path = paths::checked(&lsp.root, Path::new(key))?;
    let uri = paths::uri(&path)?;
    let arg = &command["arguments"][0];
    if arg["uri"] != uri {
        return Err(Error::new(
            "unsupported",
            "Linked name refers to a different file",
        ));
    }
    let offset = arg["offset"]
        .as_u64()
        .ok_or_else(|| Error::new("protocol", "Missing linked-name offset"))?
        as usize;
    let mut count = 0;
    let mut byte = after.len();
    for (i, ch) in after.char_indices() {
        if count == offset {
            byte = i;
            break;
        }
        count += ch.len_utf16();
        if count > offset {
            return Err(Error::new("position", "Linked name splits surrogate pair"));
        }
    }
    if count < offset {
        return Err(Error::new("position", "Linked name outside text"));
    }
    let prefix = &after[..byte];
    let line = prefix.bytes().filter(|b| *b == b'\n').count();
    let column = prefix.rsplit('\n').next().unwrap().encode_utf16().count();
    lsp.open_text(&path, after)?;
    let result=lsp.request("textDocument/rename",json!({"textDocument":{"uri":uri},"position":{"line":line,"character":column},"newName":name}));
    let restored = lsp.open_text(&path, before);
    restored?;
    let rename = result?;
    let edits = if let Some(v) = rename["changes"].get(&uri) {
        v.clone()
    } else {
        let changes = rename["documentChanges"]
            .as_array()
            .ok_or_else(|| Error::new("unsupported", "Unexpected linked rename edits"))?;
        if changes.len() != 1 || changes[0]["textDocument"]["uri"] != uri {
            return Err(Error::new(
                "unsupported",
                "Linked rename changed other files",
            ));
        }
        changes[0]["edits"].clone()
    };
    let final_text = edit::apply_text(after, &edits)?;
    let lines = before.split('\n').collect::<Vec<_>>();
    Ok(
        json!({"changes":{uri:[{"range":{"start":{"line":0,"character":0},"end":{"line":lines.len()-1,"character":lines.last().unwrap().trim_end_matches('\r').encode_utf16().count()}},"newText":final_text}]}}),
    )
}
pub fn bounded(value: Value, limit: usize) -> Value {
    if let Value::Array(mut a) = value {
        let total = a.len();
        a.truncate(limit);
        json!({"items":a,"total":total,"truncated":total>limit})
    } else {
        value
    }
}
