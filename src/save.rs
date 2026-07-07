//! Save-game persistence (roadmap 0.1).
//!
//! Scripts call `game.save(key, val)` / `game.load(key)`; the whole store is a
//! flat `string -> string|number|bool` map serialized as JSON. The codec is
//! hand-rolled (like the stdlib-only generators in tools/) so the crate gains
//! zero new dependencies for a format this small.
//!
//! Backends: a JSON file in the platform's writable dir (iOS sandbox
//! `Documents/`, desktop `$XDG_CONFIG_HOME`/`~/.config`) — and, on the web,
//! `localStorage`, since wasm has no filesystem.

use std::collections::HashMap;

/// A persistable Lua value. Lua tables must be flattened by the script
/// (e.g. `game.save("best_snake", 12)`), which keeps the format diff-friendly.
#[derive(Clone, Debug, PartialEq)]
pub enum SaveValue {
    Str(String),
    Num(f64),
    Bool(bool),
}

// ---------------------------------------------------------------------------
// Codec
// ---------------------------------------------------------------------------

fn escape_into(out: &mut String, s: &str) {
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
}

/// Serialize the store as a single JSON object. Keys are emitted sorted so the
/// output is deterministic (stable diffs, stable tests).
pub fn encode_save(map: &HashMap<String, SaveValue>) -> String {
    let mut keys: Vec<&String> = map.keys().collect();
    keys.sort();
    let mut out = String::from("{");
    for (i, key) in keys.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('"');
        escape_into(&mut out, key);
        out.push_str("\":");
        match &map[*key] {
            SaveValue::Str(s) => {
                out.push('"');
                escape_into(&mut out, s);
                out.push('"');
            }
            SaveValue::Num(n) => {
                if n.is_finite() {
                    out.push_str(&format!("{n}"));
                } else {
                    out.push('0');
                }
            }
            SaveValue::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        }
    }
    out.push('}');
    out
}

struct Parser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Parser<'a> {
    fn skip_ws(&mut self) {
        while self.pos < self.bytes.len() && self.bytes[self.pos].is_ascii_whitespace() {
            self.pos += 1;
        }
    }

    fn eat(&mut self, b: u8) -> bool {
        self.skip_ws();
        if self.pos < self.bytes.len() && self.bytes[self.pos] == b {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn peek(&mut self) -> Option<u8> {
        self.skip_ws();
        self.bytes.get(self.pos).copied()
    }

    fn string(&mut self) -> Option<String> {
        if !self.eat(b'"') {
            return None;
        }
        let mut out = String::new();
        loop {
            let b = *self.bytes.get(self.pos)?;
            self.pos += 1;
            match b {
                b'"' => return Some(out),
                b'\\' => {
                    let e = *self.bytes.get(self.pos)?;
                    self.pos += 1;
                    match e {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let hex = self.bytes.get(self.pos..self.pos + 4)?;
                            self.pos += 4;
                            let code = u32::from_str_radix(std::str::from_utf8(hex).ok()?, 16).ok()?;
                            out.push(char::from_u32(code)?);
                        }
                        _ => return None,
                    }
                }
                // Multi-byte UTF-8: copy the raw bytes through.
                b => {
                    let start = self.pos - 1;
                    let len = match b {
                        0x00..=0x7f => 1,
                        0xc0..=0xdf => 2,
                        0xe0..=0xef => 3,
                        _ => 4,
                    };
                    let chunk = self.bytes.get(start..start + len)?;
                    out.push_str(std::str::from_utf8(chunk).ok()?);
                    self.pos = start + len;
                }
            }
        }
    }

    fn value(&mut self) -> Option<SaveValue> {
        match self.peek()? {
            b'"' => self.string().map(SaveValue::Str),
            b't' => {
                self.expect_word("true")?;
                Some(SaveValue::Bool(true))
            }
            b'f' => {
                self.expect_word("false")?;
                Some(SaveValue::Bool(false))
            }
            _ => {
                let start = self.pos;
                while self
                    .bytes
                    .get(self.pos)
                    .is_some_and(|b| matches!(b, b'0'..=b'9' | b'-' | b'+' | b'.' | b'e' | b'E'))
                {
                    self.pos += 1;
                }
                std::str::from_utf8(&self.bytes[start..self.pos])
                    .ok()?
                    .parse::<f64>()
                    .ok()
                    .map(SaveValue::Num)
            }
        }
    }

    fn expect_word(&mut self, w: &str) -> Option<()> {
        self.skip_ws();
        if self.bytes[self.pos..].starts_with(w.as_bytes()) {
            self.pos += w.len();
            Some(())
        } else {
            None
        }
    }
}

/// Parse a save file back into the store. Anything malformed yields an empty
/// map — a corrupt save must never break game startup.
pub fn decode_save(text: &str) -> HashMap<String, SaveValue> {
    let mut parser = Parser {
        bytes: text.as_bytes(),
        pos: 0,
    };
    let mut map = HashMap::new();
    if !parser.eat(b'{') {
        return map;
    }
    if parser.eat(b'}') {
        return map;
    }
    loop {
        let Some(key) = parser.string() else {
            return HashMap::new();
        };
        if !parser.eat(b':') {
            return HashMap::new();
        }
        let Some(value) = parser.value() else {
            return HashMap::new();
        };
        map.insert(key, value);
        if parser.eat(b'}') {
            return map;
        }
        if !parser.eat(b',') {
            return HashMap::new();
        }
    }
}

// ---------------------------------------------------------------------------
// Storage backends
// ---------------------------------------------------------------------------

/// Where the save file lives. iOS: the app sandbox's `Documents/` (backed up,
/// survives app updates). Desktop: the XDG config dir. Tests/exotic setups
/// fall back to the working directory.
#[cfg(not(target_arch = "wasm32"))]
pub fn save_file_path() -> std::path::PathBuf {
    use std::path::PathBuf;
    #[cfg(target_os = "ios")]
    {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join("Documents").join("save.json");
        }
    }
    #[cfg(not(target_os = "ios"))]
    {
        let base = std::env::var("XDG_CONFIG_HOME")
            .map(std::path::PathBuf::from)
            .or_else(|_| std::env::var("HOME").map(|h| PathBuf::from(h).join(".config")));
        if let Ok(base) = base {
            return base.join("hollowlullaby").join("save.json");
        }
    }
    PathBuf::from("hollowlullaby_save.json")
}

/// Load the persisted store (empty on first run or on any error).
#[cfg(not(target_arch = "wasm32"))]
pub fn load_store() -> HashMap<String, SaveValue> {
    std::fs::read_to_string(save_file_path())
        .map(|text| decode_save(&text))
        .unwrap_or_default()
}

/// Write the serialized store. Errors are logged upstream, never fatal.
#[cfg(not(target_arch = "wasm32"))]
pub fn persist(json: &str) -> std::io::Result<()> {
    let path = save_file_path();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(path, json)
}

#[cfg(target_arch = "wasm32")]
const LOCAL_STORAGE_KEY: &str = "hollowlullaby_save";

#[cfg(target_arch = "wasm32")]
pub fn load_store() -> HashMap<String, SaveValue> {
    web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
        .and_then(|s| s.get_item(LOCAL_STORAGE_KEY).ok().flatten())
        .map(|text| decode_save(&text))
        .unwrap_or_default()
}

#[cfg(target_arch = "wasm32")]
pub fn persist(json: &str) -> Result<(), String> {
    let storage = web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
        .ok_or("localStorage unavailable")?;
    storage
        .set_item(LOCAL_STORAGE_KEY, json)
        .map_err(|_| "localStorage.setItem failed".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(map: &HashMap<String, SaveValue>) -> HashMap<String, SaveValue> {
        decode_save(&encode_save(map))
    }

    #[test]
    fn empty_store_roundtrips() {
        assert_eq!(roundtrip(&HashMap::new()), HashMap::new());
    }

    #[test]
    fn all_value_kinds_roundtrip() {
        let mut map = HashMap::new();
        map.insert("best_score".into(), SaveValue::Num(4200.0));
        map.insert("pi-ish".into(), SaveValue::Num(-3.5e2));
        map.insert("name".into(), SaveValue::Str("玩家一号 \"pro\"\n".into()));
        map.insert("muted".into(), SaveValue::Bool(true));
        map.insert("tutorial_done".into(), SaveValue::Bool(false));
        assert_eq!(roundtrip(&map), map);
    }

    #[test]
    fn encode_is_deterministic_sorted() {
        let mut map = HashMap::new();
        map.insert("b".into(), SaveValue::Num(2.0));
        map.insert("a".into(), SaveValue::Num(1.0));
        assert_eq!(encode_save(&map), r#"{"a":1,"b":2}"#);
    }

    #[test]
    fn corrupt_save_yields_empty_not_panic() {
        for junk in ["", "{", "not json", r#"{"k":}"#, r#"{"k" 1}"#, "[1,2]"] {
            assert!(decode_save(junk).is_empty(), "junk {junk:?} should decode empty");
        }
    }

    // The roadmap acceptance: write -> (simulated process kill) -> read back
    // identical. A fresh read from disk after `persist` IS the fresh-process
    // path (nothing survives in memory but the file).
    #[test]
    fn survives_a_simulated_process_restart() {
        let dir = std::env::temp_dir().join("hl_save_test");
        std::fs::create_dir_all(&dir).unwrap();
        std::env::set_var("XDG_CONFIG_HOME", &dir);

        let mut map = HashMap::new();
        map.insert("best".into(), SaveValue::Num(99.0));
        persist(&encode_save(&map)).unwrap();
        assert_eq!(load_store(), map, "reload from disk must match what was saved");

        map.insert("best".into(), SaveValue::Num(120.0));
        persist(&encode_save(&map)).unwrap();
        assert_eq!(load_store()["best"], SaveValue::Num(120.0), "high score must persist");
    }
}
