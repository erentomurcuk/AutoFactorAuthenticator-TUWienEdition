// AutoTISS2FA popup logic. Firefox only ever holds a finished code here —
// generation and the seed live in the native host since 1.2.

const statusEl = document.getElementById("status");
const dashboardView = document.getElementById("dashboardView");
const setupView = document.getElementById("setupView");
const seedInput = document.getElementById("seedInput");
const seedFeedback = document.getElementById("seedFeedback");
const saveBtn = document.getElementById("saveBtn");
const deleteBtn = document.getElementById("deleteBtn");
const confirmDelete = document.getElementById("confirmDelete");
const confirmYesBtn = document.getElementById("confirmYesBtn");
const confirmNoBtn = document.getElementById("confirmNoBtn");
const totpCodeEl = document.getElementById("totpCode");
const codeSubEl = document.getElementById("codeSub");
const copyBtn = document.getElementById("copyBtn");
const refreshBtn = document.getElementById("refreshBtn");
const ringValue = document.getElementById("ringValue");
const timerText = document.getElementById("timerText");
const copiedToast = document.getElementById("copiedToast");

const RING_LEN = 326.73; // 2π × r (r=52), matches popup.css
let currentOS = null;
let countdownInterval = null;
let currentCode = null;

function setStatus(text, type) {
  statusEl.textContent = text;
  statusEl.className = "status " + type;
}

function getKeychainName(os) {
  switch (os) {
    case "mac":   return "Apple Keychain";
    case "win":   return "Windows Credential Manager";
    case "linux": return "the system keyring";
    default:      return "the OS keychain";
  }
}

function linuxKeyringHint() {
  return "Install gnome-keyring, kwallet, or enable KeePassXC Secret Service plugin, then restart Firefox.";
}

// Must agree with the native host's validate_and_clean_seed: whitespace,
// dashes and '=' padding are cleaned away; '0','1','8','9' are NOT base32.
function validateBase32(str) {
  const cleaned = str.replace(/[\s=-]/g, "");
  if (cleaned.length === 0) return { valid: false, reason: "empty" };
  for (let i = 0; i < cleaned.length; i++) {
    const c = cleaned[i];
    if (!/^[A-Z2-7]$/i.test(c)) {
      return { valid: false, reason: `invalid character at position ${i + 1}: '${c}' (0, 1, 8, 9 are not base32)` };
    }
  }
  if (cleaned.length < 16 || cleaned.length > 256) {
    return { valid: false, reason: `length ${cleaned.length} is out of range (16-256)` };
  }
  return { valid: true };
}

// --- code fetching + ring countdown -----------------------------------------

function formatCode(code) {
  // "123 456" groups; the host guarantees exactly six digits.
  return code.slice(0, 3) + " " + code.slice(3);
}

function paintRing(fraction, seconds) {
  const pct = Math.max(0, Math.min(1, fraction));
  ringValue.style.strokeDashoffset = String(RING_LEN * (1 - pct));
  ringValue.classList.toggle("low", seconds <= 5);
  timerText.textContent = seconds <= 0 ? "…" : String(seconds);
}

async function fetchTOTP() {
  try {
    const result = await browser.runtime.sendMessage({ type: "request_totp" });
    if (!result || typeof result.code !== "string" || !/^\d{6}$/.test(result.code)) {
      throw new Error("bad response from native host");
    }
    currentCode = result.code;
    totpCodeEl.textContent = formatCode(currentCode);
    codeSubEl.textContent = "fresh from the host";
    startCountdown(result.expires_in || 30);
    return true;
  } catch (e) {
    console.error("TOTP fetch error:", e);
    totpCodeEl.textContent = "·· ·· ··";
    codeSubEl.textContent = "unavailable";
    currentCode = null;
    paintRing(0, 0);
    const notConfigured = e && String(e.message).includes("No seed configured");
    setStatus(notConfigured ? "No seed configured yet" : "Could not generate code: " + (e && e.message || "unknown error"), notConfigured ? "info" : "error");
    return false;
  }
}

function startCountdown(seconds) {
  if (countdownInterval) clearInterval(countdownInterval);

  const total = Math.max(1, seconds);
  let remaining = total;
  paintRing(1, remaining);

  let retryPending = false;
  async function tick() {
    remaining = Math.max(0, remaining - 1);
    paintRing(remaining / total, remaining);
    if (remaining <= 5) codeSubEl.textContent = "new code soon";
    if (remaining <= 0 && !retryPending) {
      clearInterval(countdownInterval);
      countdownInterval = null;
      // Auto-advance to the next window; retryPending keeps a failed tick and
      // a manual Refresh click from stacking two parallel fetch calls.
      retryPending = true;
      const ok = await fetchTOTP();
      retryPending = false;
      if (!ok && !countdownInterval) {
        setTimeout(() => { if (!countdownInterval) fetchTOTP(); }, 5000);
      }
    }
  }

  countdownInterval = setInterval(tick, 1000);
}

function stopCountdown() {
  if (countdownInterval) {
    clearInterval(countdownInterval);
    countdownInterval = null;
  }
  paintRing(0, 0);
}

// --- actions -----------------------------------------------------------------

copyBtn.addEventListener("click", async () => {
  if (!currentCode) return;
  try {
    await navigator.clipboard.writeText(currentCode);
    copiedToast.classList.remove("hidden");
    setTimeout(() => copiedToast.classList.add("hidden"), 1200);
  } catch {
    setStatus("Failed to copy to clipboard", "error");
  }
});

refreshBtn.addEventListener("click", () => {
  stopCountdown();
  fetchTOTP();
});

// --- seed input ----------------------------------------------------------------

seedInput.addEventListener("input", () => {
  const v = seedInput.value.trim();
  const check = validateBase32(v);
  saveBtn.disabled = !check.valid;
  seedFeedback.className = "feedback";
  if (v.length === 0) {
    seedFeedback.textContent = "";
    return;
  }
  if (check.valid) {
    seedFeedback.className = "feedback good";
    seedFeedback.textContent = `Looks valid · ${v.replace(/[\s=-]/g, "").length} base32 chars`;
  } else {
    seedFeedback.className = "feedback bad";
    seedFeedback.textContent = check.reason;
  }
});

saveBtn.addEventListener("click", async () => {
  const seed = seedInput.value.trim();
  const check = validateBase32(seed);
  if (!check.valid) {
    setStatus("Invalid base32 key: " + check.reason, "error");
    return;
  }
  saveBtn.disabled = true;
  saveBtn.textContent = "Saving…";
  try {
    const result = await browser.runtime.sendMessage({ type: "store_seed", seed });
    if (result.success) {
      seedInput.value = "";
      seedFeedback.textContent = "";
      setStatus("Seed saved", "ok");
      showDashboard();
    } else {
      const msg = currentOS === "linux" ? linuxKeyringHint() : result.message || "Unknown";
      setStatus(msg, "error");
      saveBtn.disabled = false;
      saveBtn.textContent = "Save to keychain";
    }
  } catch (e) {
    const msg = currentOS === "linux" ? linuxKeyringHint() : "Error: " + (e && e.message);
    setStatus(msg, "error");
    saveBtn.disabled = false;
    saveBtn.textContent = "Save to keychain";
  }
});

// --- delete (inline confirm) -----------------------------------------------------

deleteBtn.addEventListener("click", () => {
  deleteBtn.classList.add("hidden");
  confirmDelete.classList.remove("hidden");
});

confirmNoBtn.addEventListener("click", () => {
  confirmDelete.classList.add("hidden");
  deleteBtn.classList.remove("hidden");
});

confirmYesBtn.addEventListener("click", async () => {
  confirmYesBtn.disabled = true;
  confirmYesBtn.textContent = "Removing…";
  try {
    const result = await browser.runtime.sendMessage({ type: "delete_seed" });
    confirmDelete.classList.add("hidden");
    deleteBtn.classList.remove("hidden");
    if (result.success) {
      setStatus("Seed removed", "info");
      showSetup();
    } else {
      setStatus("Error: " + (result.message || "Unknown"), "error");
    }
  } catch (e) {
    confirmDelete.classList.add("hidden");
    deleteBtn.classList.remove("hidden");
    setStatus("Error: " + (e && e.message), "error");
  }
  confirmYesBtn.disabled = false;
  confirmYesBtn.textContent = "Remove";
});

// --- view switching + init --------------------------------------------------------

function showDashboard() {
  confirmDelete.classList.add("hidden");
  deleteBtn.classList.remove("hidden");
  dashboardView.classList.remove("hidden");
  setupView.classList.add("hidden");
  fetchTOTP();
}

function showSetup() {
  dashboardView.classList.add("hidden");
  setupView.classList.remove("hidden");
  stopCountdown();
}

async function init() {
  const info = await browser.runtime.getPlatformInfo();
  currentOS = info.os;
  document.getElementById("keychainName").textContent = getKeychainName(info.os);
  document.getElementById("keychainNameSetup").textContent = getKeychainName(info.os);
  try {
    const ping = await browser.runtime.sendMessage({ type: "ping" });
    console.log("Native host ping:", ping);
    const result = await browser.runtime.sendMessage({ type: "check_configured" });
    if (result.configured) {
      setStatus("Keychain: configured", "ok");
      showDashboard();
    } else {
      setStatus("No seed configured yet", "info");
      showSetup();
    }
  } catch (e) {
    console.error("Native host error:", e);
    const msg = currentOS === "linux" ? linuxKeyringHint() : "Native host not responding: " + ((e && e.message) || "unknown");
    setStatus(msg, "error");
    // The host must be reachable to save a seed, so leave the setup view up
    // (with the save button disabled) instead of a menu-less error box.
    showSetup();
    saveBtn.disabled = true;
    saveBtn.textContent = "Save to keychain";
  }
}

init();
