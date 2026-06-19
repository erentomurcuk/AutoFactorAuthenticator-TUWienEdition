const NATIVE_HOST = "com.tuwel.2fa";

function base32Decode(str) {
  const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  str = str.replace(/[=\s-]/g, "").toUpperCase();
  const bytes = [];
  let buffer = 0, bitsLeft = 0;
  for (const char of str) {
    const val = ALPHABET.indexOf(char);
    if (val === -1) continue;
    buffer = (buffer << 5) | val;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      bytes.push((buffer >> (bitsLeft - 8)) & 0xFF);
      bitsLeft -= 8;
    }
  }
  return new Uint8Array(bytes);
}

function intTo8Bytes(num) {
  const bytes = new Uint8Array(8);
  for (let i = 7; i >= 0; i--) {
    bytes[i] = num & 0xFF;
    num >>>= 8;
  }
  return bytes;
}

async function generateTOTP(seed) {
  const decodedSeed = base32Decode(seed);
  const counter = Math.floor(Date.now() / 1000 / 30);
  const counterBytes = intTo8Bytes(counter);
  const key = await crypto.subtle.importKey("raw", decodedSeed, { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, counterBytes);
  const hmac = new Uint8Array(sig);
  const offset = hmac[19] & 0xF;
  const code = ((hmac[offset] & 0x7F) << 24) | (hmac[offset + 1] << 16) | (hmac[offset + 2] << 8) | hmac[offset + 3];
  return String(code % 1000000).padStart(6, "0");
}

let lastTOTP = null;
let lastCounter = -1;

browser.runtime.onMessage.addListener((msg, sender) => {
  if (msg.type === "request_totp") {
    const counter = Math.floor(Date.now() / 1000 / 30);
    if (lastTOTP && lastCounter === counter) {
      return Promise.resolve(lastTOTP);
    }
    return browser.runtime.sendNativeMessage(NATIVE_HOST, { command: "get_seed" }).then(async (response) => {
      if (response.status === "ok" && response.data) {
        const code = await generateTOTP(response.data);
        lastTOTP = code;
        lastCounter = counter;
        return code;
      }
      throw new Error(response.message || "Seed not configured");
    });
  }
});

browser.runtime.onMessage.addListener((msg) => {
  if (msg.type === "check_configured") {
    return browser.runtime.sendNativeMessage(NATIVE_HOST, { command: "check" }).then((r) => ({
      configured: r.status === "ok" && !!r.data,
      message: r.message,
    })).catch((e) => ({ configured: false, message: e.message }));
  }
  if (msg.type === "store_seed") {
    return browser.runtime.sendNativeMessage(NATIVE_HOST, { command: "store_seed", seed: msg.seed }).then((r) => ({
      success: r.status === "ok",
      message: r.message,
    }));
  }
  if (msg.type === "delete_seed") {
    return browser.runtime.sendNativeMessage(NATIVE_HOST, { command: "delete_seed" }).then((r) => ({
      success: r.status === "ok",
      message: r.message,
    }));
  }
});
