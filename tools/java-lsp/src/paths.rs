use crate::error::{Error, Result};
use std::{
    env, fs,
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::{Component, Path, PathBuf},
    process::Command,
};

pub fn root(explicit: Option<&str>) -> Result<PathBuf> {
    let path = if let Some(p) = explicit {
        PathBuf::from(p)
    } else {
        let out = Command::new("git")
            .args(["rev-parse", "--show-toplevel"])
            .output()?;
        if !out.status.success() {
            return Err(Error::new(
                "root_required",
                "Use --root outside a Git worktree",
            ));
        }
        PathBuf::from(
            String::from_utf8(out.stdout)
                .map_err(|_| Error::new("path", "Root must be UTF-8"))?
                .trim_end(),
        )
    };
    let path = path.canonicalize()?;
    if !path.is_dir() {
        return Err(Error::new("path", "Root is not a directory"));
    }
    Ok(path)
}
pub fn text(path: &Path) -> Result<&str> {
    path.to_str()
        .ok_or_else(|| Error::new("path", "Paths must be UTF-8"))
}
pub fn uri(path: &Path) -> Result<String> {
    let mut out = "file://".to_owned();
    for b in text(path)?.bytes() {
        if b.is_ascii_alphanumeric() || b"/-._~".contains(&b) {
            out.push(b as char)
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    Ok(out)
}
pub fn from_uri(value: &str) -> Result<PathBuf> {
    let value = value
        .strip_prefix("file://")
        .ok_or_else(|| Error::new("path", "Only file URIs can be edited"))?;
    if !value.starts_with('/') {
        return Err(Error::new("path", "Remote file URI rejected"));
    }
    let mut bytes = vec![];
    let mut i = 0;
    let raw = value.as_bytes();
    while i < raw.len() {
        if raw[i] == b'%' {
            if i + 2 >= raw.len() {
                return Err(Error::new("path", "Invalid URI escape"));
            }
            let s = std::str::from_utf8(&raw[i + 1..i + 3])
                .map_err(|_| Error::new("path", "Invalid URI"))?;
            bytes.push(
                u8::from_str_radix(s, 16).map_err(|_| Error::new("path", "Invalid URI escape"))?,
            );
            i += 3;
        } else {
            bytes.push(raw[i]);
            i += 1;
        }
    }
    Ok(PathBuf::from(
        String::from_utf8(bytes).map_err(|_| Error::new("path", "URI must be UTF-8"))?,
    ))
}
pub fn checked(root: &Path, input: &Path) -> Result<PathBuf> {
    let path = if input.is_absolute() {
        input.to_owned()
    } else {
        root.join(input)
    };
    if path
        .components()
        .any(|c| matches!(c, Component::ParentDir | Component::CurDir))
    {
        return Err(Error::new("path", "Use normalized paths without . or .."));
    }
    let rel = path
        .strip_prefix(root)
        .map_err(|_| Error::new("path", "Path is outside project root"))?;
    if rel.as_os_str().is_empty() {
        return Err(Error::new("path", "Cannot edit project root"));
    }
    let mut current = root.to_owned();
    for part in rel.components() {
        current.push(part);
        match fs::symlink_metadata(&current) {
            Ok(m) if m.file_type().is_symlink() => {
                return Err(Error::new("path", "Symlinks cannot be edited"));
            }
            Ok(_) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.into()),
        }
    }
    Ok(path)
}
fn private(path: &Path) -> Result<()> {
    fs::create_dir_all(path)?;
    let m = fs::symlink_metadata(path)?;
    let uid = fs::metadata("/proc/self")?.uid();
    if m.file_type().is_symlink() || m.uid() != uid {
        return Err(Error::new(
            "permissions",
            "State directory must be owned by this user and not a symlink",
        ));
    }
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}
pub struct Paths {
    pub socket: PathBuf,
    pub runtime: PathBuf,
    pub state: PathBuf,
    pub cache: PathBuf,
}
impl Paths {
    pub fn new(root: &Path) -> Result<Self> {
        let home = env::var_os("HOME").ok_or_else(|| Error::new("environment", "HOME missing"))?;
        // Stable FNV-1a key; the full root stored alongside it detects collisions.
        let mut hash = 0xcbf29ce484222325u64;
        for b in text(root)?.bytes() {
            hash ^= b as u64;
            hash = hash.wrapping_mul(0x100000001b3);
        }
        let key = format!("{hash:016x}");
        let runtime_base = env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(format!(
                    "/tmp/java-lsp-{}",
                    fs::metadata("/proc/self")
                        .map(|m| m.uid())
                        .unwrap_or(u32::MAX)
                ))
            });
        let runtime = runtime_base.join("java-lsp").join(&key);
        let state = env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(&home).join(".local/state"))
            .join("java-lsp")
            .join(&key);
        let cache = env::var_os("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(home).join(".cache"))
            .join("java-lsp")
            .join(&key);
        let socket = runtime.join("rpc");
        if text(&socket)?.len() > 100 {
            return Err(Error::new(
                "path",
                "Runtime socket path too long; use shorter XDG_RUNTIME_DIR",
            ));
        }
        Ok(Self {
            socket,
            runtime,
            state,
            cache,
        })
    }
    pub fn create(&self, root: &Path) -> Result<()> {
        for p in [&self.runtime, &self.state, &self.cache] {
            private(p)?;
            use std::io::{Read, Write};
            let mut record = fs::OpenOptions::new()
                .read(true)
                .write(true)
                .create(true)
                .truncate(false)
                .open(p.join("root"))?;
            record.lock()?;
            let mut existing = String::new();
            record.read_to_string(&mut existing)?;
            if existing.is_empty() {
                record.write_all(text(root)?.as_bytes())?;
                record.sync_all()?;
            } else if existing != text(root)? {
                return Err(Error::new(
                    "collision",
                    "State key belongs to another project",
                ));
            }
        }
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn uri_roundtrip() {
        let p = Path::new("/tmp/a b/😀.java");
        assert_eq!(from_uri(&uri(p).unwrap()).unwrap(), p);
    }
    #[test]
    fn rejects_remote_uri() {
        assert!(from_uri("file://host/tmp/x").is_err());
    }
}
