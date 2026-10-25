use crate::{
    error::{Error, Result},
    paths, wire,
};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    io::BufReader,
    path::{Path, PathBuf},
    process::{Child, ChildStdin, Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant},
};

pub struct Lsp {
    child: Child,
    input: ChildStdin,
    events: Receiver<Result<Value>>,
    next: u64,
    pub capabilities: Value,
    pub server_info: Value,
    pub status: Value,
    pub diagnostics: BTreeMap<String, Value>,
    pub documents: BTreeMap<String, (String, i64)>,
    files: BTreeMap<PathBuf, (u64, std::time::SystemTime)>,
    pub generation: u64,
    pub diagnostic_generation: BTreeMap<String, u64>,
    pub settings: Value,
    pub root: PathBuf,
    pub timeout: Duration,
    pub started: bool,
    pub failure: Option<String>,
}
impl Lsp {
    pub fn spawn(root: &Path, cache: &Path, log: &Path, init_timeout: Duration) -> Result<Self> {
        let executable = std::env::var_os("JAVA_LSP_JDTLS").unwrap_or_else(|| "jdtls".into());
        let stderr = fs::OpenOptions::new().create(true).append(true).open(log)?;
        let mut child = Command::new(executable)
            .arg("--jvm-arg=-Djava.import.generatesMetadataFilesAtProjectRoot=false")
            .arg("-data")
            .arg(cache.join("jdtls"))
            .current_dir(root)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(stderr)
            .spawn()?;
        let input = child.stdin.take().unwrap();
        let stdout = child.stdout.take().unwrap();
        let (tx, events) = mpsc::sync_channel(256);
        thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                let result = wire::read(&mut reader);
                let failed = result.is_err();
                if tx.send(result).is_err() || failed {
                    break;
                }
            }
        });
        let settings = json!({"java":{"import":{"generatesMetadataFilesAtProjectRoot":false,"gradle":{"enabled":true,"wrapper":{"enabled":true}}},"configuration":{"updateBuildConfiguration":"automatic"},"autobuild":{"enabled":true},"signatureHelp":{"enabled":true},"format":{"enabled":true},"references":{"includeDecompiledSources":false}}});
        let mut this = Self {
            child,
            input,
            events,
            next: 0,
            capabilities: Value::Null,
            server_info: Value::Null,
            status: json!({"type":"Starting"}),
            diagnostics: BTreeMap::new(),
            documents: BTreeMap::new(),
            files: BTreeMap::new(),
            generation: 0,
            diagnostic_generation: BTreeMap::new(),
            settings,
            root: root.to_owned(),
            timeout: init_timeout,
            started: false,
            failure: None,
        };
        let uri = paths::uri(root)?;
        let result=this.request("initialize",json!({"processId":std::process::id(),"clientInfo":{"name":"java-lsp","version":env!("CARGO_PKG_VERSION")},"rootUri":uri,"workspaceFolders":[{"uri":uri,"name":root.file_name().and_then(|s|s.to_str()).unwrap_or("project")}],"capabilities":{"workspace":{"applyEdit":false,"configuration":true,"workspaceFolders":true,"didChangeWatchedFiles":{"dynamicRegistration":true},"workspaceEdit":{"documentChanges":true,"resourceOperations":["create","rename","delete"],"failureHandling":"abort"}},"textDocument":{"synchronization":{"dynamicRegistration":false,"didSave":true},"publishDiagnostics":{"versionSupport":true},"definition":{"linkSupport":true},"codeAction":{"codeActionLiteralSupport":{"codeActionKind":{"valueSet":["quickfix","refactor","refactor.extract","refactor.inline","source.organizeImports"]}},"resolveSupport":{"properties":["edit"]}},"rename":{"prepareSupport":true}},"window":{"workDoneProgress":true},"general":{"positionEncodings":["utf-16"]}},"initializationOptions":{"settings":this.settings,"extendedClientCapabilities":{"progressReportProvider":true,"classFileContentsSupport":true,"advancedExtractRefactoringSupport":true,"advancedOrganizeImportsSupport":false,"moveRefactoringSupport":true,"changeSignatureSupport":true,"extractInterfaceSupport":true}}}))?;
        this.capabilities = result["capabilities"].clone();
        this.server_info = result["serverInfo"].clone();
        if let Some(enc) = this.capabilities["positionEncoding"].as_str()
            && enc != "utf-16"
        {
            return Err(Error::new(
                "unsupported",
                format!("Unexpected position encoding {enc}"),
            ));
        }
        this.notify("initialized", json!({}))?;
        this.notify(
            "workspace/didChangeConfiguration",
            json!({"settings":this.settings}),
        )?;
        let deadline = Instant::now() + init_timeout;
        while !this.started {
            if Instant::now() >= deadline {
                return Err(Error::new(
                    "indexing_timeout",
                    "JDT LS did not report Started before deadline",
                )
                .detail(this.status.clone()));
            }
            this.pump(Duration::from_millis(100))?;
        }
        this.timeout = Duration::from_secs(60);
        this.sync()?;
        Ok(this)
    }
    pub fn notify(&mut self, method: &str, params: Value) -> Result<()> {
        wire::write(
            &mut self.input,
            &json!({"jsonrpc":"2.0","method":method,"params":params}),
        )
    }
    fn handle(&mut self, value: Value) -> Result<()> {
        let Some(method) = value["method"].as_str() else {
            return Ok(());
        };
        if let Some(id) = value.get("id") {
            let response = match method {
                "workspace/configuration" => {
                    let items = value["params"]["items"]
                        .as_array()
                        .cloned()
                        .unwrap_or_default();
                    json!({"result":items.iter().map(|i|{let mut v=&self.settings;if let Some(s)=i["section"].as_str(){for part in s.split('.') {v=&v[part];}}v.clone()}).collect::<Vec<_>>()})
                }
                "workspace/workspaceFolders" => {
                    json!({"result":[{"uri":paths::uri(&self.root)?,"name":"project"}]})
                }
                "client/registerCapability"
                | "client/unregisterCapability"
                | "window/workDoneProgress/create" => json!({"result":null}),
                "workspace/applyEdit" => {
                    json!({"result":{"applied":false,"failureReason":"Edits require a java-lsp preview plan"}})
                }
                "window/showMessageRequest" => json!({"result":null}),
                _ => {
                    json!({"error":{"code":-32601,"message":format!("Unsupported client method: {method}")}})
                }
            };
            let mut response = response;
            response["jsonrpc"] = json!("2.0");
            response["id"] = id.clone();
            wire::write(&mut self.input, &response)?;
        } else {
            match method {
                "language/status" => {
                    self.status = value["params"].clone();
                    if self.status["type"] == "Started" {
                        self.started = true;
                    }
                }
                "textDocument/publishDiagnostics" => {
                    if let Some(uri) = value["params"]["uri"].as_str() {
                        let version = value["params"]["version"].as_i64();
                        let current = self.documents.get(uri).map(|d| d.1);
                        if version.is_some() && current.is_some() && version != current {
                            return Ok(());
                        }
                        self.diagnostics.insert(uri.into(), value["params"].clone());
                        self.diagnostic_generation
                            .insert(uri.into(), self.generation);
                    }
                }
                "language/progressReport" => {
                    self.status["progress"] = value["params"].clone();
                }
                _ => {}
            }
        }
        Ok(())
    }
    pub fn pump(&mut self, wait: Duration) -> Result<()> {
        match self.events.recv_timeout(wait) {
            Ok(Ok(v)) => self.handle(v),
            Ok(Err(e)) => {
                self.failure = Some(e.to_string());
                Err(e)
            }
            Err(mpsc::RecvTimeoutError::Timeout) => Ok(()),
            Err(_) => Err(Error::new("disconnected", "JDT LS reader stopped")),
        }
    }
    pub fn request(&mut self, method: &str, params: Value) -> Result<Value> {
        if let Some(message) = &self.failure {
            return Err(Error::new("disconnected", message.clone()));
        }
        self.next += 1;
        let id = self.next;
        wire::write(
            &mut self.input,
            &json!({"jsonrpc":"2.0","id":id,"method":method,"params":params}),
        )?;
        let deadline = Instant::now() + self.timeout;
        loop {
            let remain = deadline.saturating_duration_since(Instant::now());
            if remain.is_zero() {
                let _ = self.notify("$/cancelRequest", json!({"id":id}));
                return Err(Error::new("timeout", format!("Timed out: {method}")));
            }
            match self.events.recv_timeout(remain) {
                Ok(Ok(v)) => {
                    if v["id"] == id && v.get("method").is_none() {
                        if let Some(err) = v.get("error") {
                            return Err(Error::new(
                                "server",
                                format!("{method}: {}", err["message"]),
                            )
                            .detail(err.clone()));
                        }
                        return Ok(v["result"].clone());
                    }
                    self.handle(v)?;
                }
                Ok(Err(e)) => {
                    self.failure = Some(e.to_string());
                    return Err(e);
                }
                Err(mpsc::RecvTimeoutError::Timeout) => continue,
                Err(_) => return Err(Error::new("disconnected", "JDT LS stopped")),
            }
        }
    }
    pub fn open_text(&mut self, path: &Path, text: &str) -> Result<String> {
        let uri = paths::uri(path)?;
        match self.documents.get(&uri).cloned() {
            Some((old, version)) => {
                if old != text {
                    let version = version + 1;
                    self.notify("textDocument/didChange",json!({"textDocument":{"uri":uri,"version":version},"contentChanges":[{"text":text}]}))?;
                    self.documents.insert(uri.clone(), (text.into(), version));
                    self.diagnostic_generation.remove(&uri);
                }
            }
            None => {
                self.notify(
                    "textDocument/didOpen",
                    json!({"textDocument":{"uri":uri,"languageId":"java","version":1,"text":text}}),
                )?;
                self.documents.insert(uri.clone(), (text.into(), 1));
                self.diagnostic_generation.remove(&uri);
            }
        }
        Ok(uri)
    }
    pub fn open(&mut self, path: &Path) -> Result<String> {
        let text = fs::read_to_string(path)?;
        self.open_text(path, &text)
    }
    pub fn verify_snapshot(&self) -> Result<()> {
        let mut current = BTreeMap::new();
        scan(&self.root, &mut current)?;
        if current != self.files {
            return Err(Error::new(
                "stale_analysis",
                "Source or build files changed during the operation; retry",
            ));
        }
        for (uri, (text, _)) in &self.documents {
            if fs::read_to_string(paths::from_uri(uri)?)? != *text {
                return Err(Error::new(
                    "stale_analysis",
                    "An open source changed during the operation; retry",
                ));
            }
        }
        Ok(())
    }

    pub fn sync(&mut self) -> Result<Value> {
        let mut files = BTreeMap::new();
        scan(&self.root, &mut files)?;
        let mut changes = vec![];
        let mut build = vec![];
        for (p, stamp) in &files {
            if self.files.get(p) != Some(stamp) {
                changes.push(
                    json!({"uri":paths::uri(p)?,"type":if self.files.contains_key(p){2}else{1}}),
                );
                if p.extension().and_then(|x| x.to_str()) != Some("java") {
                    build.push(json!({"uri":paths::uri(p)?}));
                }
            }
        }
        for p in self.files.keys() {
            if !files.contains_key(p) {
                changes.push(json!({"uri":paths::uri(p)?,"type":3}));
            }
        }
        let docs = self.documents.keys().cloned().collect::<Vec<_>>();
        for uri in docs {
            let p = paths::from_uri(&uri)?;
            if p.exists() {
                self.open(&p)?;
            } else {
                self.notify("textDocument/didClose", json!({"textDocument":{"uri":uri}}))?;
                self.documents.remove(&uri);
                self.diagnostics.remove(&uri);
            }
        }
        if !changes.is_empty() {
            self.generation += 1;
            self.diagnostic_generation.clear();
            self.notify(
                "workspace/didChangeWatchedFiles",
                json!({"changes":changes}),
            )?;
            if !self.files.is_empty() && !build.is_empty() {
                self.notify(
                    "java/projectConfigurationsUpdate",
                    json!({"identifiers":build}),
                )?;
            }
        }
        self.files = files;
        Ok(json!({"changed":changes.len(),"generation":self.generation}))
    }
    pub fn diagnostic(&mut self, uri: &str) -> Result<Value> {
        while let Ok(event) = self.events.try_recv() {
            self.handle(event?)?;
        }
        self.diagnostic_generation.remove(uri);
        self.notify("java/validateDocument", json!({"textDocument":{"uri":uri}}))?;
        let deadline = Instant::now() + self.timeout;
        while self.diagnostic_generation.get(uri) != Some(&self.generation) {
            if Instant::now() >= deadline {
                return Ok(
                    json!({"uri":uri,"fresh":false,"reason":"No diagnostic publication before deadline","last":self.diagnostics.get(uri),"status":self.status}),
                );
            }
            self.pump(Duration::from_millis(100))?;
        }
        Ok(
            json!({"uri":uri,"fresh":true,"freshness":"publication_received_after_validation_request","version_verified":self.diagnostics.get(uri).is_some_and(|v|v["version"].is_number()),"generation":self.generation,"publication":self.diagnostics.get(uri),"status":self.status,"note":"Diagnostic publication is not a successful project build"}),
        )
    }
    pub fn shutdown(&mut self) {
        self.timeout = Duration::from_secs(3);
        let _ = self.request("shutdown", Value::Null);
        let _ = self.notify("exit", Value::Null);
    }
}
impl Drop for Lsp {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
fn scan(dir: &Path, out: &mut BTreeMap<PathBuf, (u64, std::time::SystemTime)>) -> Result<()> {
    for e in fs::read_dir(dir)? {
        let e = e?;
        let ty = e.file_type()?;
        if ty.is_symlink() {
            continue;
        }
        let p = e.path();
        if ty.is_dir() {
            if matches!(
                e.file_name().to_str(),
                Some(
                    ".git"
                        | ".gradle"
                        | ".metadata"
                        | ".settings"
                        | "target"
                        | "build"
                        | "out"
                        | "node_modules"
                        | ".java-lsp"
                )
            ) {
                continue;
            }
            scan(&p, out)?;
        } else if ty.is_file() {
            let name = e.file_name();
            let name = name.to_string_lossy();
            if name.ends_with(".java")
                || matches!(
                    name.as_ref(),
                    "pom.xml"
                        | "build.gradle"
                        | "build.gradle.kts"
                        | "settings.gradle"
                        | "settings.gradle.kts"
                        | "gradle.properties"
                        | ".classpath"
                        | ".project"
                )
            {
                if out.len() >= 100_000 {
                    return Err(Error::new(
                        "too_large",
                        "Project exceeds 100000 tracked source/build files",
                    ));
                }
                let m = e.metadata()?;
                out.insert(p, (m.len(), m.modified()?));
            }
        }
    }
    Ok(())
}
