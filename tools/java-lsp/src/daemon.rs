use crate::{
    api, edit,
    error::{Error, Result, required},
    lsp::Lsp,
    paths::{self, Paths},
    wire,
};
use serde_json::{Value, json};
use std::{
    fs,
    io::BufReader,
    os::unix::net::{UnixListener, UnixStream},
    path::Path,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

fn envelope(result: Result<Value>) -> Value {
    match result {
        Ok(v) => json!({"ok":true,"result":v}),
        Err(e) => json!({"ok":false,"error":e.json()}),
    }
}
pub fn serve(root: &Path) -> Result<()> {
    let paths = Paths::new(root)?;
    paths.create(root)?;
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(paths.runtime.join("daemon.lock"))?;
    lock.try_lock()
        .map_err(|_| Error::new("already_running", "Another daemon owns this workspace"))?;
    if paths.socket.exists() {
        fs::remove_file(&paths.socket)?;
    }
    let listener = UnixListener::bind(&paths.socket)?;
    listener.set_nonblocking(true)?;
    let mut lsp: Option<Lsp> = None;
    let mut last = Instant::now();
    loop {
        match listener.accept() {
            Ok((mut socket, _)) => {
                socket.set_read_timeout(Some(Duration::from_secs(10)))?;
                socket.set_write_timeout(Some(Duration::from_secs(10)))?;
                let request = wire::read(&mut BufReader::new(socket.try_clone()?));
                let mut stop = false;
                let result = request.and_then(|r| {
                    if r["root"] != paths::text(root)? {
                        return Err(Error::new(
                            "root_mismatch",
                            "Daemon belongs to another root",
                        ));
                    }
                    if r["command"] == "stop" {
                        stop = true;
                        return Ok(json!({"stopped": true}));
                    }
                    dispatch(root, &paths, &mut lsp, &r)
                });
                if let Err(error) = wire::write(&mut socket, &envelope(result))
                    && error.code == "too_large"
                {
                    let _ = wire::write(&mut socket, &envelope(Err(error)));
                }
                last = Instant::now();
                if stop {
                    break;
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                if let Some(ls) = lsp.as_mut()
                    && ls.failure.is_none()
                    && let Err(e) = ls.pump(Duration::from_millis(10))
                {
                    ls.failure = Some(e.to_string());
                }
                if last.elapsed() > Duration::from_secs(1800) {
                    break;
                }
                thread::sleep(Duration::from_millis(20));
            }
            Err(e) => return Err(e.into()),
        }
    }
    if let Some(ls) = lsp.as_mut() {
        ls.shutdown();
    }
    drop(lsp);
    fs::remove_file(&paths.socket)?;
    Ok(())
}
fn ensure_lsp<'a>(
    root: &Path,
    paths: &Paths,
    slot: &'a mut Option<Lsp>,
    request: &Value,
) -> Result<&'a mut Lsp> {
    if slot.is_none() {
        *slot = Some(Lsp::spawn(
            root,
            &paths.cache,
            &paths.state.join("jdtls.log"),
            Duration::from_secs(request["options"]["init-timeout"].as_u64().unwrap_or(300)),
        )?);
    }
    Ok(slot.as_mut().unwrap())
}

fn dispatch(root: &Path, paths: &Paths, lsp: &mut Option<Lsp>, request: &Value) -> Result<Value> {
    let command = required(request, "command")?;
    if command == "status" {
        return Ok(json!({
            "pid": std::process::id(), "root": paths::text(root)?, "running": true,
            "initialized": lsp.is_some(), "server": lsp.as_ref().map(|l| &l.server_info),
            "status": lsp.as_ref().map(|l| &l.status),
            "failure": lsp.as_ref().and_then(|l| l.failure.as_ref()),
            "recovery_required": edit::pending(&paths.state)?
        }));
    }
    if command == "plan" {
        let id = required(request, "plan_id")?;
        let operation = required(request, "operation")?;
        if operation == "show" {
            return edit::show(&edit::load(&paths.state, id)?);
        }
        if !["apply", "recover"].contains(&operation) {
            return Err(Error::new("usage", "Unknown plan operation"));
        }
        let mut result = edit::apply(&paths.state, root, id, operation == "recover")?;
        // Application is committed before analysis. A server failure must never imply
        // that the already-applied transaction can be retried.
        let analysis = (|| -> Result<Value> {
            if operation == "recover" {
                if let Some(ls) = lsp.as_mut() {
                    ls.sync()?;
                }
                return Ok(
                    json!({"fresh": false, "reason": "Recovery completed; run the project checks"}),
                );
            }
            let ls = ensure_lsp(root, paths, lsp, request)?;
            ls.sync()?;
            let timeout = Duration::from_secs(request["options"]["timeout"].as_u64().unwrap_or(60));
            let deadline = Instant::now() + timeout;
            let mut publications = Vec::new();
            for value in result["files"].as_array().unwrap() {
                let path = paths::checked(root, Path::new(value.as_str().unwrap()))?;
                if path.extension().and_then(|s| s.to_str()) != Some("java") || !path.exists() {
                    continue;
                }
                let remaining = deadline.saturating_duration_since(Instant::now());
                if remaining.is_zero() {
                    return Ok(
                        json!({"publications": publications, "complete": false, "reason": "Post-apply diagnostic deadline reached"}),
                    );
                }
                ls.timeout = remaining;
                let uri = ls.open(&path)?;
                publications.push(ls.diagnostic(&uri)?);
            }
            Ok(json!({"publications": publications, "complete": true}))
        })();
        result["diagnostics"] = match analysis {
            Ok(v) => v,
            Err(e) => json!({"fresh": false, "error": e.json()}),
        };
        return Ok(result);
    }
    let ls = ensure_lsp(root, paths, lsp, request)?;
    if command == "start" {
        return Ok(json!({"started": true, "root": paths::text(root)?, "status": ls.status}));
    }
    api::run(ls, &paths.state, request).map(|v| {
        api::bounded(
            v,
            request["options"]["limit"].as_u64().unwrap_or(200) as usize,
        )
    })
}

fn launch(root: &Path, paths: &Paths) -> Result<()> {
    paths.create(root)?;
    let log = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(paths.state.join("daemon.log"))?;
    Command::new(std::env::current_exe()?)
        .arg("__serve")
        .arg(root)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(log)
        .spawn()?;
    let deadline = Instant::now() + Duration::from_secs(10);
    while Instant::now() < deadline {
        if UnixStream::connect(&paths.socket).is_ok() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(50));
    }
    Err(Error::new(
        "startup_timeout",
        format!(
            "Daemon did not start; see {}",
            paths.state.join("daemon.log").display()
        ),
    ))
}
pub fn call(root: &Path, mut request: Value) -> Result<Value> {
    let paths = Paths::new(root)?;
    if request["command"] == "plan" && request["operation"] == "show" {
        return Ok(envelope(
            edit::load(&paths.state, required(&request, "plan_id")?).and_then(|p| edit::show(&p)),
        ));
    }
    if request["command"] == "restart" {
        let mut stop = request.clone();
        stop["command"] = json!("stop");
        let _ = call(root, stop)?;
        let deadline = Instant::now() + Duration::from_secs(10);
        while paths.socket.exists() && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(50));
        }
        request["command"] = json!("start");
    }
    let mut stream = match UnixStream::connect(&paths.socket) {
        Ok(s) => s,
        Err(_) => {
            if request["command"] == "status" || request["command"] == "stop" {
                return Ok(envelope(Ok(
                    json!({"running":false,"root":paths::text(root)?}),
                )));
            }
            launch(root, &paths)?;
            UnixStream::connect(&paths.socket)?
        }
    };
    request["root"] = json!(paths::text(root)?);
    let timeout = Duration::from_secs(
        request["options"]["timeout"].as_u64().unwrap_or(60)
            + request["options"]["init-timeout"].as_u64().unwrap_or(300) * 2
            + 10,
    );
    stream.set_read_timeout(Some(timeout))?;
    stream.set_write_timeout(Some(Duration::from_secs(10)))?;
    wire::write(&mut stream, &request)?;
    wire::read(&mut BufReader::new(stream))
}
