use crate::{
    error::{Error, Result, required},
    paths,
};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};
const MAX_FILE: u64 = 8 * 1024 * 1024;
const MAX_FILES: usize = 512;

pub fn offset(text: &str, pos: &Value) -> Result<usize> {
    let line = pos["line"]
        .as_u64()
        .ok_or_else(|| Error::new("position", "Missing line"))? as usize;
    let col = pos["character"]
        .as_u64()
        .ok_or_else(|| Error::new("position", "Missing character"))? as usize;
    let mut start = 0;
    for _ in 0..line {
        start += text[start..]
            .find('\n')
            .ok_or_else(|| Error::new("position", "Line out of range"))?
            + 1;
    }
    let slice = text[start..]
        .split('\n')
        .next()
        .unwrap_or("")
        .trim_end_matches('\r');
    let mut units = 0;
    for (i, ch) in slice.char_indices() {
        if units == col {
            return Ok(start + i);
        }
        units += ch.len_utf16();
        if units > col {
            return Err(Error::new("position", "Position splits a surrogate pair"));
        }
    }
    if units == col {
        Ok(start + slice.len())
    } else {
        Err(Error::new("position", "Column out of range"))
    }
}
pub fn position(text: &str, input: &str) -> Result<Value> {
    let (l, c) = input
        .split_once(':')
        .ok_or_else(|| Error::new("position", "Expected LINE:COLUMN"))?;
    let line = l
        .parse::<usize>()
        .ok()
        .filter(|x| *x > 0)
        .ok_or_else(|| Error::new("position", "Line must be positive"))?
        - 1;
    let col = c
        .parse::<usize>()
        .ok()
        .filter(|x| *x > 0)
        .ok_or_else(|| Error::new("position", "Column must be positive"))?
        - 1;
    let slice = text
        .split('\n')
        .nth(line)
        .ok_or_else(|| Error::new("position", "Line out of range"))?
        .trim_end_matches('\r');
    if col > slice.chars().count() {
        return Err(Error::new("position", "Column out of range"));
    }
    Ok(json!({"line":line,"character":slice.chars().take(col).map(char::len_utf16).sum::<usize>()}))
}
pub fn apply_text(text: &str, edits: &Value) -> Result<String> {
    let edits = edits
        .as_array()
        .ok_or_else(|| Error::new("edit", "Expected text edits array"))?;
    let mut ranges = vec![];
    for (order, e) in edits.iter().enumerate() {
        let s = offset(text, &e["range"]["start"])?;
        let end = offset(text, &e["range"]["end"])?;
        if end < s {
            return Err(Error::new("edit", "Reversed range"));
        }
        ranges.push((s, end, order, required(e, "newText")?));
    }
    ranges.sort_by_key(|r| (r.0, r.1, r.2));
    for w in ranges.windows(2) {
        if w[1].0 < w[0].1 {
            return Err(Error::new("edit", "Overlapping text edits"));
        }
    }
    let mut out = text.to_owned();
    for (s, e, _, t) in ranges.into_iter().rev() {
        out.replace_range(s..e, t);
    }
    Ok(out)
}
fn read(path: &Path) -> Result<Value> {
    match fs::symlink_metadata(path) {
        Ok(m) => {
            if !m.is_file() || m.file_type().is_symlink() {
                return Err(Error::new("edit", "Only regular files can be edited"));
            }
            if m.len() > MAX_FILE {
                return Err(Error::new("too_large", "File exceeds 8 MiB"));
            }
            Ok(json!({"text":fs::read_to_string(path)?,"mode":m.permissions().mode()&0o777}))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Value::Null),
        Err(e) => Err(e.into()),
    }
}
fn touch(root: &Path, map: &mut BTreeMap<String, Value>, uri: &str) -> Result<String> {
    let path = paths::checked(root, &paths::from_uri(uri)?)?;
    let key = paths::text(path.strip_prefix(root).unwrap())?.to_owned();
    if !map.contains_key(&key) {
        if map.len() >= MAX_FILES {
            return Err(Error::new("too_large", "Plan exceeds 512 files"));
        }
        let before = read(&path)?;
        map.insert(key.clone(), json!({"before":before,"after":before}));
    }
    Ok(key)
}
fn text_change(
    root: &Path,
    map: &mut BTreeMap<String, Value>,
    uri: &str,
    edits: &Value,
) -> Result<()> {
    let key = touch(root, map, uri)?;
    let f = map.get_mut(&key).unwrap();
    let source = f["after"]["text"]
        .as_str()
        .ok_or_else(|| Error::new("edit", "Text edit targets a missing file"))?;
    let output = apply_text(source, edits)?;
    if output.len() as u64 > MAX_FILE {
        return Err(Error::new("too_large", "Edited file exceeds 8 MiB"));
    }
    f["after"]["text"] = json!(output);
    Ok(())
}
pub fn materialize(root: &Path, edit: &Value) -> Result<Value> {
    if edit["changes"].as_object().is_some_and(|v| !v.is_empty())
        && edit["documentChanges"]
            .as_array()
            .is_some_and(|v| !v.is_empty())
    {
        return Err(Error::new(
            "edit",
            "Ambiguous workspace edit contains both changes representations",
        ));
    }
    let mut map = BTreeMap::new();
    if let Some(changes) = edit["changes"].as_object() {
        for (uri, edits) in changes {
            text_change(root, &mut map, uri, edits)?;
        }
    }
    if let Some(changes) = edit["documentChanges"].as_array() {
        for change in changes {
            match change["kind"].as_str() {
                None => text_change(
                    root,
                    &mut map,
                    required(&change["textDocument"], "uri")?,
                    &change["edits"],
                )?,
                Some("create") => {
                    let k = touch(root, &mut map, required(change, "uri")?)?;
                    let f = map.get_mut(&k).unwrap();
                    if !f["after"].is_null() {
                        return Err(Error::new("conflict", "Create target exists"));
                    }
                    f["after"] = json!({"text":"","mode":0o644});
                }
                Some("rename") => {
                    let a = touch(root, &mut map, required(change, "oldUri")?)?;
                    let b = touch(root, &mut map, required(change, "newUri")?)?;
                    if map[&a]["after"].is_null() || !map[&b]["after"].is_null() {
                        return Err(Error::new(
                            "conflict",
                            "Rename source missing or destination exists",
                        ));
                    }
                    let value = map[&a]["after"].clone();
                    map.get_mut(&a).unwrap()["after"] = Value::Null;
                    map.get_mut(&b).unwrap()["after"] = value;
                }
                Some("delete") => {
                    let k = touch(root, &mut map, required(change, "uri")?)?;
                    if map[&k]["after"].is_null() {
                        return Err(Error::new("conflict", "Delete target missing"));
                    }
                    map.get_mut(&k).unwrap()["after"] = Value::Null;
                }
                Some(_) => return Err(Error::new("unsupported", "Unknown resource operation")),
            }
        }
    }
    map.retain(|_, f| f["before"] != f["after"]);
    if map.is_empty() {
        return Err(Error::new("no_changes", "Server returned no changes"));
    }
    Ok(json!(map))
}
fn atomic_json(path: &Path, value: &Value) -> Result<()> {
    let temp = path.with_extension("tmp");
    let bytes = serde_json::to_vec(value)?;
    if bytes.len() > crate::wire::MAX_MESSAGE {
        return Err(Error::new("too_large", "Plan exceeds 32 MiB"));
    }
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(&temp)?;
    fs::set_permissions(&temp, fs::Permissions::from_mode(0o600))?;
    f.write_all(&bytes)?;
    f.sync_all()?;
    fs::rename(&temp, path)?;
    fs::File::open(path.parent().unwrap())?.sync_all()?;
    Ok(())
}
pub fn save(state: &Path, root: &Path, operation: &str, edit: &Value) -> Result<Value> {
    let files = materialize(root, edit)?;
    let id = format!(
        "{:x}-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
        std::process::id()
    );
    let plan = json!({"schema":1,"id":id,"root":paths::text(root)?,"operation":operation,"status":"preview","files":files,"annotations":edit["changeAnnotations"]});
    fs::create_dir_all(state.join("plans"))?;
    atomic_json(&state.join("plans").join(format!("{id}.json")), &plan)?;
    show(&plan)
}
pub fn load(state: &Path, id: &str) -> Result<Value> {
    if id.is_empty() || !id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        return Err(Error::new("invalid_input", "Invalid plan ID"));
    }
    let path = state.join("plans").join(format!("{id}.json"));
    if fs::metadata(&path)?.len() > crate::wire::MAX_MESSAGE as u64 {
        return Err(Error::new("too_large", "Plan exceeds limit"));
    }
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}
pub fn show(plan: &Value) -> Result<Value> {
    let mut diff = String::new();
    let files = plan["files"]
        .as_object()
        .ok_or_else(|| Error::new("plan", "Invalid plan files"))?;
    for (path, f) in files {
        let before = f["before"]["text"].as_str().unwrap_or("");
        let after = f["after"]["text"].as_str().unwrap_or("");
        let a = if f["before"].is_null() {
            "/dev/null".into()
        } else {
            format!("a/{path}")
        };
        let b = if f["after"].is_null() {
            "/dev/null".into()
        } else {
            format!("b/{path}")
        };
        diff.push_str(&format!(
            "--- {a}\n+++ {b}\n@@ -{},{} +{},{} @@\n",
            usize::from(!before.is_empty()),
            before.lines().count(),
            usize::from(!after.is_empty()),
            after.lines().count()
        ));
        for (prefix, content) in [('-', before), ('+', after)] {
            for line in content.split_inclusive('\n') {
                diff.push(prefix);
                diff.push_str(line);
                if !line.ends_with('\n') {
                    diff.push_str("\n\\ No newline at end of file\n");
                }
            }
        }
    }
    Ok(
        json!({"plan_id":plan["id"],"status":plan["status"],"operation":plan["operation"],"files":files.keys().collect::<Vec<_>>(),"diff":diff,"annotations":plan["annotations"]}),
    )
}
pub fn pending(state: &Path) -> Result<Option<String>> {
    let dir = state.join("plans");
    if !dir.exists() {
        return Ok(None);
    }
    for e in fs::read_dir(dir)? {
        let path = e?.path();
        if path.extension().and_then(|s| s.to_str()) != Some("json") {
            continue;
        }
        let p: Value = serde_json::from_slice(&fs::read(&path)?)?;
        if p["status"] == "applying" || p["status"] == "recovering" {
            return Ok(p["id"].as_str().map(str::to_owned));
        }
    }
    Ok(None)
}
fn replace(root: &Path, key: &str, value: &Value) -> Result<()> {
    let path = paths::checked(root, Path::new(key))?;
    if value.is_null() {
        if path.exists() {
            fs::remove_file(&path)?;
            fs::File::open(path.parent().unwrap())?.sync_all()?;
        }
        return Ok(());
    }
    fs::create_dir_all(path.parent().unwrap())?;
    let path = paths::checked(root, Path::new(key))?;
    let tmp = path.with_file_name(format!(
        ".java-lsp-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp)?;
    let result = (|| -> Result<()> {
        f.write_all(required(value, "text")?.as_bytes())?;
        f.set_permissions(fs::Permissions::from_mode(
            value["mode"].as_u64().unwrap_or(0o644) as u32,
        ))?;
        f.sync_all()?;
        fs::rename(&tmp, &path)?;
        fs::File::open(path.parent().unwrap())?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(tmp);
    }
    result
}
pub fn apply(state: &Path, root: &Path, id: &str, recover: bool) -> Result<Value> {
    let mut plan = load(state, id)?;
    if plan["root"] != paths::text(root)? {
        return Err(Error::new("plan", "Plan belongs to another project"));
    }
    if recover {
        if plan["status"] != "applying" && plan["status"] != "recovering" {
            return Err(Error::new("plan_state", "Plan does not require recovery"));
        }
    } else {
        if let Some(id) = pending(state)? {
            return Err(Error::new(
                "recovery_required",
                format!("Run plan recover {id}"),
            ));
        }
        if plan["status"] != "preview" {
            return Err(Error::new("plan_state", "Plan is no longer applicable"));
        }
    }
    let files = plan["files"]
        .as_object()
        .ok_or_else(|| Error::new("plan", "Invalid plan"))?
        .clone();
    for (key, f) in &files {
        let current = read(&paths::checked(root, Path::new(key))?)?;
        if current != f["before"] && (!recover || current != f["after"]) {
            return Err(Error::new(
                "stale_plan",
                format!("Changed since preview: {key}"),
            ));
        }
    }
    let path = state.join("plans").join(format!("{id}.json"));
    plan["status"] = json!(if recover { "recovering" } else { "applying" });
    atomic_json(&path, &plan)?;
    let target = if recover { "before" } else { "after" };
    for (key, f) in &files {
        let current = read(&paths::checked(root, Path::new(key))?)?;
        if current != f["before"] && (!recover || current != f["after"]) {
            return Err(Error::new(
                "recovery_required",
                format!("Concurrent edit to {key}; inspect and recover {id}"),
            ));
        }
        replace(root, key, &f[target]).map_err(|e| {
            Error::new("recovery_required", e.to_string()).detail(json!({"plan_id":id}))
        })?;
    }
    plan["status"] = json!(if recover { "rolled_back" } else { "applied" });
    atomic_json(&path, &plan)?;
    Ok(json!({"plan_id":id,"status":plan["status"],"files":files.keys().collect::<Vec<_>>()}))
}
#[cfg(test)]
mod tests {
    use super::*;
    fn temp() -> std::path::PathBuf {
        let p = std::env::temp_dir().join(format!(
            "java-lsp-edit-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&p).unwrap();
        p
    }
    #[test]
    fn unicode_and_crlf() {
        let s = "😀a\r\nb";
        assert_eq!(position(s, "1:2").unwrap(), json!({"line":0,"character":2}));
        assert_eq!(offset(s, &json!({"line":1,"character":0})).unwrap(), 7);
        assert!(offset(s, &json!({"line":0,"character":1})).is_err());
    }
    #[test]
    fn overlapping_edits_rejected() {
        let e = json!([{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":2}},"newText":"x"},{"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":2}},"newText":"y"}]);
        assert!(apply_text("abc", &e).is_err());
    }
    #[test]
    fn ordered_rename_edit_and_stale_plan() {
        let root = temp();
        let state = temp();
        fs::write(root.join("A.java"), "abc").unwrap();
        let edit = json!({"documentChanges":[{"kind":"rename","oldUri":paths::uri(&root.join("A.java")).unwrap(),"newUri":paths::uri(&root.join("B.java")).unwrap()},{"textDocument":{"uri":paths::uri(&root.join("B.java")).unwrap(),"version":null},"edits":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":3}},"newText":"xyz"}]}]});
        let preview = save(&state, &root, "test", &edit).unwrap();
        assert_eq!(fs::read_to_string(root.join("A.java")).unwrap(), "abc");
        let id = preview["plan_id"].as_str().unwrap();
        fs::write(root.join("A.java"), "changed").unwrap();
        assert_eq!(
            apply(&state, &root, id, false).unwrap_err().code,
            "stale_plan"
        );
        fs::write(root.join("A.java"), "abc").unwrap();
        apply(&state, &root, id, false).unwrap();
        assert_eq!(fs::read_to_string(root.join("B.java")).unwrap(), "xyz");
        assert!(!root.join("A.java").exists());
        assert!(apply(&state, &root, id, false).is_err());
        fs::remove_dir_all(root).unwrap();
        fs::remove_dir_all(state).unwrap();
    }
    #[test]
    fn recovery_refuses_intervening_edit() {
        let root = temp();
        let state = temp();
        fs::write(root.join("A"), "old").unwrap();
        let e = json!({"changes":{paths::uri(&root.join("A")).unwrap():[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":3}},"newText":"new"}]}});
        let p = save(&state, &root, "test", &e).unwrap();
        let id = p["plan_id"].as_str().unwrap();
        let mut plan = load(&state, id).unwrap();
        plan["status"] = json!("applying");
        atomic_json(&state.join("plans").join(format!("{id}.json")), &plan).unwrap();
        fs::write(root.join("A"), "third").unwrap();
        assert!(apply(&state, &root, id, true).is_err());
        fs::write(root.join("A"), "new").unwrap();
        apply(&state, &root, id, true).unwrap();
        assert_eq!(fs::read_to_string(root.join("A")).unwrap(), "old");
        fs::remove_dir_all(root).unwrap();
        fs::remove_dir_all(state).unwrap();
    }
    #[test]
    fn rejects_symlink() {
        let root = temp();
        std::os::unix::fs::symlink("/tmp", root.join("escape")).unwrap();
        assert!(paths::checked(&root, Path::new("escape/a")).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
