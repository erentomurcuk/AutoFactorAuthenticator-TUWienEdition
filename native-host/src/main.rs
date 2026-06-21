use std::env;
use std::io::{self, Read, Write};
use std::process;
use byteorder::{LittleEndian, ReadBytesExt, WriteBytesExt};
use serde::{Deserialize, Serialize};

const SERVICE: &str = "TU Wien Auto 2FA";
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

fn validate_and_clean_seed(s: &str) -> Result<String, String> {
    let cleaned: String = s.chars().filter(|c| !c.is_whitespace() && *c != '-').collect();
    let upper = cleaned.to_uppercase();
    if upper.len() < MIN_SEED_SIZE || upper.len() > MAX_SEED_SIZE {
        return Err(format!("Seed length {} is out of range ({}-{})", upper.len(), MIN_SEED_SIZE, MAX_SEED_SIZE));
    }
    for (i, c) in upper.char_indices() {
        if c == '=' {
            if i < upper.len() - 6 {
                return Err(format!("padding '=' at position {}", i + 1));
            }
            continue;
        }
        if !matches!(c, 'A'..='Z' | '2'..='7') {
            return Err(format!("invalid character at position {}: '{}' (code {})", i + 1, c, c as u32));
        }
    }
    Ok(upper)
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

fn unknown_command(_cmd: &str) -> Response {
    Response { status: "error".into(), data: None, message: Some("Unknown command".into()) }
}

fn delete_stored_seed() -> io::Result<()> {
    match keyring::Entry::new(SERVICE, SEED_KEY) {
        Ok(entry) => {
            match entry.delete_credential() {
                Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
                Err(e) => Err(io::Error::new(io::ErrorKind::Other, e)),
            }
        }
        Err(e) => Err(io::Error::new(io::ErrorKind::Other, e)),
    }
}

fn print_help() {
    eprintln!("TU Wien Auto 2FA native host");
    eprintln!("");
    eprintln!("When launched by Firefox with no arguments, this binary speaks the");
    eprintln!("Native Messaging protocol on stdin/stdout.");
    eprintln!("");
    eprintln!("Options:");
    eprintln!("  --delete-credential  Remove the stored TOTP seed from the OS keychain");
    eprintln!("  --help               Show this help message");
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    // Firefox passes the manifest path as the first argument on macOS.
    // Ignore it and start the native messaging loop.
    if args.len() > 1 {
        match args[1].as_str() {
            "--delete-credential" => {
                if let Err(e) = delete_stored_seed() {
                    eprintln!("Failed to remove credential: {e}");
                    process::exit(1);
                }
                println!("Removed stored TOTP seed from keychain.");
                return Ok(());
            }
            "--help" | "-h" => {
                print_help();
                return Ok(());
            }
            _ => {
                // Firefox passes the manifest JSON path as an argument.
                // Ignore it and fall through to the native messaging loop.
            }
        }
    }

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
                match validate_and_clean_seed(seed) {
                    Err(detail) => {
                        let msg = format!("Invalid seed format: {}", detail);
                        write_message(&Response { status: "error".into(), data: None, message: Some(msg) })?;
                        continue;
                    }
                    Ok(clean_seed) => {
                        match keyring::Entry::new(SERVICE, SEED_KEY) {
                            Ok(entry) => {
                                match entry.set_password(&clean_seed) {
                                    Ok(()) => Response { status: "ok".into(), data: None, message: None },
                                    Err(_) => keyring_error(),
                                }
                            }
                            Err(_) => keyring_error(),
                        }
                    }
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
