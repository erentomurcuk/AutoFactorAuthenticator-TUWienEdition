use std::env;
use std::io::{self, Read, Write};
use std::process;
use byteorder::{LittleEndian, ReadBytesExt, WriteBytesExt};
use serde::{Deserialize, Serialize};

// Variant identity: this keyring service belongs to the AutoTISS2FA build of
// AutoFactorAuthenticator. OLD_SERVICE is kept so --delete-credential also
// cleans up seeds stored by the pre-rename build ("TU Wien Auto 2FA").
const SERVICE: &str = "AutoTISS2FA";
const OLD_SERVICE: &str = "TU Wien Auto 2FA";
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
    // Whitespace, dashes and padding are presentation; the stored value is
    // canonical uppercase base32 without them. (Before 1.2 the '=' survived
    // validation and got stored inside the keyring entry - harmless only
    // because the JS still stripped '=' at read time.)
    let cleaned: String = s
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '-' && *c != '=')
        .collect();
    let upper = cleaned.to_uppercase();
    if upper.len() < MIN_SEED_SIZE || upper.len() > MAX_SEED_SIZE {
        return Err(format!("Seed length {} is out of range ({}-{})", upper.len(), MIN_SEED_SIZE, MAX_SEED_SIZE));
    }
    for (i, c) in upper.char_indices() {
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
    // Remove the current service name, and the pre-rename one as well, so an
    // upgrade can never leave the old seed orphaned in the keychain.
    for service in [SERVICE, OLD_SERVICE] {
        match keyring::Entry::new(service, SEED_KEY) {
            Ok(entry) => {
                match entry.delete_credential() {
                    Ok(()) | Err(keyring::Error::NoEntry) => {}
                    Err(e) => {
                        return Err(io::Error::new(io::ErrorKind::Other, e));
                    }
                }
            }
            Err(e) => return Err(io::Error::new(io::ErrorKind::Other, e)),
        }
    }
    Ok(())
}

fn print_help() {
    eprintln!("AutoTISS2FA native host (AutoFactorAuthenticator)");
    eprintln!("");
    eprintln!("When launched by Firefox with no arguments, this binary speaks the");
    eprintln!("Native Messaging protocol on stdin/stdout.");
    eprintln!("");
    eprintln!("Options:");
    eprintln!("  --delete-credential  Remove the stored TOTP seed from the OS keychain");
    eprintln!("  --version            Show the version and exit");
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
            "--version" | "-V" => {
                println!("autotiss2fa-native {}", env!("CARGO_PKG_VERSION"));
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
            "probe" => {
                // Actually exercise the keyring backend so the launcher can
                // tell whether libsecret (or the platform equivalent) is
                // usable. NoEntry counts as success: the backend is
                // reachable, just empty.
                match keyring::Entry::new(SERVICE, SEED_KEY) {
                    Ok(entry) => {
                        match entry.get_password() {
                            Ok(_) => Response { status: "ok".into(), data: Some("reachable".into()), message: None },
                            Err(keyring::Error::NoEntry) => Response { status: "ok".into(), data: Some("reachable".into()), message: None },
                            Err(e) => Response { status: "error".into(), data: None, message: Some(format!("Keyring error: {e}").chars().take(256).collect()) },
                        }
                    }
                    Err(_) => keyring_error(),
                }
            }
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
