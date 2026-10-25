use serde_json::{Value, json};
use std::fmt;

#[derive(Debug)]
pub struct Error {
    pub code: String,
    pub message: String,
    pub details: Value,
}
pub type Result<T> = std::result::Result<T, Error>;
impl Error {
    pub fn new(code: &str, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            details: Value::Null,
        }
    }
    pub fn detail(mut self, details: Value) -> Self {
        self.details = details;
        self
    }
    pub fn json(&self) -> Value {
        json!({"code":self.code,"message":self.message,"details":self.details})
    }
}
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}
impl std::error::Error for Error {}
impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Self::new("io", e.to_string())
    }
}
impl From<serde_json::Error> for Error {
    fn from(e: serde_json::Error) -> Self {
        Self::new("json", e.to_string())
    }
}
pub fn required<'a>(v: &'a Value, key: &str) -> Result<&'a str> {
    v[key]
        .as_str()
        .ok_or_else(|| Error::new("invalid_input", format!("Missing string: {key}")))
}
