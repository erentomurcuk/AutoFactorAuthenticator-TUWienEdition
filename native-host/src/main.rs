use std::io::{self, Read, Write};
use byteorder::{LittleEndian, ReadBytesExt, WriteBytesExt};
use serde::{Deserialize, Serialize};

const SERVICE: &str = "TUWien Auto 2FA";
const SEED_KEY: &str = "totp_seed";
const MAX_MESSAGE_SIZE: usize = 4_194_304;
const MAX_SEED_SIZE: usize = 256;
const MIN_SEED_SIZE: usize = 16;

#[derive(Deserialize)]
struct Request {
    command: String,
    seed: Option<String>,
}

#[derive(Serialize)]
struct Response {
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

fn is_valid_base32(s: &str) -> bool {
    let cleaned: String = s.chars().filter(|c| !c.is_whitespace() && *c != '-').collect();
    if cleaned.len() < MIN_SEED_SIZE || cleaned.len() > MAX_SEED_SIZE {
        return false;
    }
    for (i, c) in cleaned.char_indices() {
        if c == '=' {
            return i >= cleaned.len() - 6 && cleaned[i..].chars().all(|x| x == '=');
        }
        if !matches!(c, 'A'..='Z' | '2'..='7') {
            return false;
        }
    }
    true
}

fn read_message() -> io::Result<Option<Request>> {
    let stdin = io::stdin();
    let mut handle = stdin.lock();
    let raw = match handle.read_u32::<LittleEndian>() {
        Ok(len) => len as usize,
        Err(ref e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e),
    };
    if raw > MAX_MESSAGE_SIZE {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "message too large"));
    }
    let mut buf = vec![0u8; raw];
    handle.read_exact(&mut buf)?;
    Ok(Some(serde_json::from_slice(&buf).map_err(|e| {
        io::Error::new(io::ErrorKind::InvalidData, e)
    })?))
}

fn write_message(msg: &Response) -> io::Result<()> {
    let data = serde_json::to_vec(msg).map_err(|e| {
        io::Error::new(io::ErrorKind::Other, e)
    })?;
    let stdout = io::stdout();
    let mut handle = stdout.lock();
    handle.write_u32::<LittleEndian>(data.len() as u32)?;
    handle.write_all(&data)?;
    handle.flush()?;
    Ok(())
}

fn keyring_ok() -> Response {
    Response { status: "ok".into(), data: Some("configured".into()), message: None }
}

fn keyring_error() -> Response {
    Response { status: "error".into(), data: None, message: Some("Keychain error".into()) }
}

fn not_found() -> Response {
    Response { status: "error".into(), data: None, message: Some("No seed configured".into()) }
}

fn missing_seed() -> Response {
    Response { status: "error".into(), data: None, message: Some("Missing seed".into()) }
}

fn invalid_seed() -> Response {
    Response { status: "error".into(), data: None, message: Some("Invalid seed format".into()) }
}

fn unknown_command(_cmd: &str) -> Response {
    Response { status: "error".into(), data: None, message: Some("Unknown command".into()) }
}

fn main() -> io::Result<()> {
    loop {
        let msg = match read_message()? {
            Some(m) => m,
            None => break,
        };
        let response = match msg.command.as_str() {
            "ping" => Response {
                status: "ok".into(),
                data: Some("pong".into()),
                message: None,
            },
            "check" => {
                match keyring::Entry::new(SERVICE, SEED_KEY) {
                    Ok(entry) => {
                        match entry.get_password() {
                            Ok(_) => keyring_ok(),
                            Err(keyring::Error::NoEntry) => {
                                Response { status: "ok".into(), data: None, message: Some("No seed configured".into()) }
                            }
                            Err(_) => keyring_error(),
                        }
                    }
                    Err(_) => keyring_error(),
                }
            }
            "get_seed" => {
                match keyring::Entry::new(SERVICE, SEED_KEY) {
                    Ok(entry) => {
                        match entry.get_password() {
                            Ok(pw) => Response { status: "ok".into(), data: Some(pw), message: None },
                            Err(keyring::Error::NoEntry) => not_found(),
                            Err(_) => keyring_error(),
                        }
                    }
                    Err(_) => keyring_error(),
                }
            }
            "store_seed" => {
                let seed = match &msg.seed {
                    Some(s) => s,
                    None => {
                        write_message(&missing_seed())?;
                        continue;
                    }
                };
                if !is_valid_base32(seed) {
                    write_message(&invalid_seed())?;
                    continue;
                }
                match keyring::Entry::new(SERVICE, SEED_KEY) {
                    Ok(entry) => {
                        match entry.set_password(seed) {
                            Ok(()) => Response { status: "ok".into(), data: None, message: None },
                            Err(_) => keyring_error(),
                        }
                    }
                    Err(_) => keyring_error(),
                }
            }
            "delete_seed" => {
                match keyring::Entry::new(SERVICE, SEED_KEY) {
                    Ok(entry) => {
                        match entry.delete_credential() {
                            Ok(()) => Response { status: "ok".into(), data: None, message: None },
                            Err(keyring::Error::NoEntry) => Response { status: "ok".into(), data: None, message: None },
                            Err(_) => keyring_error(),
                        }
                    }
                    Err(_) => keyring_error(),
                }
            }
            _ => unknown_command(&msg.command),
        };
        write_message(&response)?;
    }
    Ok(())
}
