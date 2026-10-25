use crate::error::{Error, Result};
use serde_json::Value;
use std::io::{BufRead, Write};
pub const MAX_MESSAGE: usize = 32 * 1024 * 1024;
pub fn read(reader: &mut impl BufRead) -> Result<Value> {
    let mut length = None;
    let mut total = 0;
    loop {
        let mut line = Vec::new();
        let n = std::io::Read::take(&mut *reader, 8193).read_until(b'\n', &mut line)?;
        if n == 0 {
            return Err(Error::new("disconnected", "Protocol stream closed"));
        }
        total += n;
        if total > 8192 {
            return Err(Error::new("protocol", "Header exceeds 8 KiB"));
        }
        if line == b"\r\n" || line == b"\n" {
            break;
        }
        let line =
            std::str::from_utf8(&line).map_err(|_| Error::new("protocol", "Non-ASCII header"))?;
        if let Some((key, value)) = line.split_once(':')
            && key.eq_ignore_ascii_case("Content-Length")
        {
            if length.is_some() {
                return Err(Error::new("protocol", "Duplicate Content-Length"));
            }
            length = Some(
                value
                    .trim()
                    .parse::<usize>()
                    .map_err(|_| Error::new("protocol", "Invalid Content-Length"))?,
            );
        }
    }
    let len = length.ok_or_else(|| Error::new("protocol", "Missing Content-Length"))?;
    if len > MAX_MESSAGE {
        return Err(Error::new("too_large", "Protocol message exceeds 32 MiB"));
    }
    let mut bytes = vec![0; len];
    reader.read_exact(&mut bytes)?;
    Ok(serde_json::from_slice(&bytes)?)
}
pub fn write(writer: &mut impl Write, value: &Value) -> Result<()> {
    let bytes = serde_json::to_vec(value)?;
    if bytes.len() > MAX_MESSAGE {
        return Err(Error::new("too_large", "Protocol message exceeds 32 MiB"));
    }
    write!(writer, "Content-Length: {}\r\n\r\n", bytes.len())?;
    writer.write_all(&bytes)?;
    writer.flush()?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::io::Cursor;
    #[test]
    fn frames_unicode_and_multiple_messages() {
        let mut out = vec![];
        write(&mut out, &json!({"x":"😀"})).unwrap();
        write(&mut out, &json!(2)).unwrap();
        let mut c = Cursor::new(out);
        assert_eq!(read(&mut c).unwrap(), json!({"x":"😀"}));
        assert_eq!(read(&mut c).unwrap(), json!(2));
    }
    #[test]
    fn rejects_duplicate_and_oversized_headers() {
        for s in [
            "Content-Length: 0\r\nContent-Length: 0\r\n\r\n",
            "Content-Length: 999999999\r\n\r\n",
        ] {
            assert!(read(&mut Cursor::new(s)).is_err());
        }
    }
}
