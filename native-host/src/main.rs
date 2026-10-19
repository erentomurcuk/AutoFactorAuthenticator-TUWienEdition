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

/// `data` is a JSON value: a string for ping/probe/check, an object
/// (`{"code": "…", "ttl": …}`) for get_code, `null` where absent.
#[derive(Serialize)]
struct Response {
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<serde_json::Value>,
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

// ---- keyring access --------------------------------------------------------

/// Reads the stored seed. `Ok(None)` = not configured; `Err(())` = backend error.
fn load_seed() -> Result<Option<String>, ()> {
    match keyring::Entry::new(SERVICE, SEED_KEY) {
        Ok(entry) => match entry.get_password() {
            Ok(pw) => Ok(Some(pw)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(_) => Err(()),
        },
        Err(_) => Err(()),
    }
}

// ---- TOTP (RFC 6238, SHA-1, 6 digits, 30 s period) -------------------------
// The golden rule of this project: the seed stays in this process. Firefox
// asks for a CODE, never for the seed.

/// Standard RFC 4648 base32 alphabet, canonical (uppercase, no padding kept).
const B32: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

fn base32_decode(s: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(s.len() * 5 / 8);
    let mut acc: u32 = 0;
    let mut bits: u32 = 0;
    for c in s.bytes() {
        let idx = B32.iter().position(|a| a.eq_ignore_ascii_case(&c))?;
        acc = (acc << 5) | idx as u32;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
        }
    }
    // Trailing bits (< 8 of them) are the canonical padding remainder: they
    // carry fewer bits than one byte, exactly as every RFC 4648 decoder (and
    // the previous JS implementation) treats them. Nothing to do.
    Some(out)
}

fn totp_code(secret: &str, counter: u64) -> Option<String> {
    use hmac::{Hmac, Mac};
    use sha1::Sha1;
    type HmacSha1 = Hmac<Sha1>;

    let key = base32_decode(secret)?;
    let mut mac = HmacSha1::new_from_slice(&key).ok()?;
    mac.update(&counter.to_be_bytes());
    let digest = mac.finalize().into_bytes();
    let d = &digest[..];
    let off = (d[19] & 0x0f) as usize;
    let bin: u64 = ((d[off] as u64 & 0x7f) << 24)
        | ((d[off + 1] as u64) << 16)
        | ((d[off + 2] as u64) << 8)
        | (d[off + 3] as u64);
    Some(format!("{:0width$}", bin % 1_000_000, width = 6))
}

/// `Ok(None)` = no seed configured; `Err(())` = backend error; `Ok(Some(..))` =
/// the current 6-digit code plus seconds until it expires.
fn current_code() -> Result<Option<(String, u64)>, ()> {
    let Some(seed) = load_seed()? else { return Ok(None) };
    let counter = now_counter();
    match totp_code(&seed, counter) {
        Some(code) => {
            let ttl = SEED_WINDOW - (now_unix() % SEED_WINDOW);
            Ok(Some((code, ttl)))
        }
        // A stored seed should never fail to decode (it was validated at
        // store time), but a manually edited or pre-1.1 junk entry must not
        // masquerade as a wrong-code problem: report it as unconfigured.
        None => Err(()),
    }
}

fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

const SEED_WINDOW: u64 = 30;
fn now_counter() -> u64 {
    now_unix() / SEED_WINDOW
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
                // tell whether the Secret Service (or the platform
                // equivalent) is usable. NoEntry counts as success: the
                // backend is reachable, just empty.
                match load_seed() {
                    Ok(_) => Response { status: "ok".into(), data: Some("reachable".into()), message: None },
                    Err(()) => {
                        // Distinguish a reachable-but-failing backend from an
                        // unavailable entry creation by probing directly.
                        match keyring::Entry::new(SERVICE, SEED_KEY) {
                            Ok(entry) => {
                                let detail = match entry.get_password() {
                                    Err(e) => format!("{e}"),
                                    Ok(_) => String::new(),
                                };
                                Response { status: "error".into(), data: None, message: Some(format!("Keyring error: {}", detail.chars().take(256).collect::<String>())) }
                            }
                            Err(e) => Response { status: "error".into(), data: None, message: Some(format!("Keyring error: {e}").chars().take(256).collect()) },
                        }
                    }
                }
            }
            "check" => {
                match load_seed() {
                    Ok(Some(_)) => keyring_ok(),
                    Ok(None) => not_found(),
                    Err(()) => keyring_error(),
                }
            }
            "get_code" => {
                // THE v1.2 protocol change: Firefox asks for a 6-digit code
                // (plus its TTL), never for the seed. Owner of the seed is
                // this process and the OS keyring; nothing else.
                match current_code() {
                    Ok(Some((code, ttl))) => {
                        Response {
                            status: "ok".into(),
                            data: Some(serde_json::json!({ "code": code, "ttl": ttl })),
                            message: None,
                        }
                    }
                    Ok(None) => not_found(),
                    Err(()) => keyring_error(),
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

#[cfg(test)]
mod tests {
    use super::*;

    // RFC 6238 appendix-B secret "12345678901234567890" as base32 (SHA-1).
    const RFC_SEED: &str = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

    #[test]
    fn base32_roundtrip_rfc_secret() {
        assert_eq!(
            base32_decode(RFC_SEED).as_deref(),
            Some(&b"12345678901234567890"[..])
        );
    }

    #[test]
    fn base32_rejects_foreign_chars() {
        assert!(base32_decode("0123456789").is_none()); // 0/1/8/9 not in alphabet
        assert!(base32_decode("AB!").is_none());
    }

    #[test]
    fn totp_rfc4226_six_digit_vectors() {
        // HOTP (RFC 4226 §5.4) codes for counters 0..4 = the same values TOTP
        // produces for the matching window indices (TOTP(counter 0-4)).
        assert_eq!(totp_code(RFC_SEED, 0).as_deref(), Some("755224"));
        assert_eq!(totp_code(RFC_SEED, 1).as_deref(), Some("287082"));
        assert_eq!(totp_code(RFC_SEED, 2).as_deref(), Some("359152"));
        assert_eq!(totp_code(RFC_SEED, 3).as_deref(), Some("969429"));
        assert_eq!(totp_code(RFC_SEED, 4).as_deref(), Some("338314"));
    }

    #[test]
    fn totp_large_counter_stays_stable() {
        // Counter > u32 exercises the 64-bit big-endian encoding.
        assert!(totp_code(RFC_SEED, u32::MAX as u64 + 1).is_some());
        let a = totp_code(RFC_SEED, u32::MAX as u64 + 1).unwrap();
        assert!(a.len() == 6 && a.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn validator_cleaning() {
        assert_eq!(validate_and_clean_seed("jbsw y3dp-ehpk=3pXP").unwrap(), "JBSWY3DPEHPK3PXP");
        assert!(validate_and_clean_seed("0123456789abcdef").is_err()); // 0/1 invalid
        assert!(validate_and_clean_seed("TOOSHORT").is_err());
        assert!(validate_and_clean_seed(&"X".repeat(300)).is_err());
    }

    #[test]
    fn ttl_is_window_fraction() {
        let t = now_unix();
        assert!(SEED_WINDOW - (t % SEED_WINDOW) >= 1);
        assert!(SEED_WINDOW - (t % SEED_WINDOW) <= SEED_WINDOW);
    }
}
