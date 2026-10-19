// AutoTISS2FA background script.
//
// Since 1.2 the TOTP arithmetic lives in the native host (get_code). This
// script holds NO crypto, NO seed material, and never asks the host for the
// seed — Firefox only ever sees a finished 6-digit code and its TTL.
//
// Keep in sync with the host name in the native-messaging manifest written by
// the installers (com.autofactor.autotiss2fa.json / the registry key on
// Windows). A mismatch shows up as "Access to the specified native messaging
// host is not allowed".
const NATIVE_HOST = "com.autofactor.autotiss2fa";

const POPUP_URL = browser.runtime.getURL("popup/popup.html");

function isPopup(sender) {
  return sender.id === browser.runtime.id && !!sender.url && sender.url.startsWith(POPUP_URL);
}

function native(command, extra) {
  return browser.runtime.sendNativeMessage(NATIVE_HOST, Object.assign({ command }, extra || {}));
}

// Normalises a native-host reply into a plain failure so callers cannot
// mistake a malformed response for a success (the shape is guarded, not
// trusted — mirrors how the popup treats our replies).
function unwrap(r) {
  if (!r || r.status !== "ok") {
    throw new Error((r && r.message) || "Native host error");
  }
  return r.data;
}

browser.runtime.onMessage.addListener((msg, sender) => {
  if (sender.id !== browser.runtime.id) return;

  if (msg.type === "request_totp") {
    return native("get_code")
      .then((r) => {
        const data = unwrap(r);
        // data: {"code": "123456", "ttl": seconds-left}. Guard the shape; the
        // host's own validation was already unit-tested against RFC 4226.
        if (!data || typeof data.code !== "string" || !/^\d{6}$/.test(data.code)
            || typeof data.ttl !== "number" || !(data.ttl >= 1 && data.ttl <= 30)) {
          throw new Error("malformed get_code response");
        }
        return { code: data.code, expires_in: data.ttl };
      });
  }

  if (msg.type === "ping") {
    return native("ping").then((r) => ({ success: r.status === "ok", message: r.message }));
  }

  if (msg.type === "check_configured") {
    return native("check")
      .then((r) => ({ configured: r.status === "ok" && !!r.data, message: r.message }))
      .catch((e) => ({ configured: false, message: e.message }));
  }

  if (msg.type === "store_seed") {
    if (!isPopup(sender)) return Promise.resolve({ success: false, message: "Not allowed" });
    return native("store_seed", { seed: msg.seed }).then((r) => ({
      success: r.status === "ok",
      message: r.message,
    }));
  }

  if (msg.type === "delete_seed") {
    if (!isPopup(sender)) return Promise.resolve({ success: false, message: "Not allowed" });
    return native("delete_seed").then((r) => ({
      success: r.status === "ok",
      message: r.message,
    }));
  }
});
