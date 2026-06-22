const statusEl = document.getElementById("status");
const dashboardView = document.getElementById("dashboardView");
const setupView = document.getElementById("setupView");
const seedInput = document.getElementById("seedInput");
const saveBtn = document.getElementById("saveBtn");
const deleteBtn = document.getElementById("deleteBtn");
const confirmDelete = document.getElementById("confirmDelete");
const confirmYesBtn = document.getElementById("confirmYesBtn");
const confirmNoBtn = document.getElementById("confirmNoBtn");
const totpCodeEl = document.getElementById("totpCode");
const copyBtn = document.getElementById("copyBtn");
const refreshBtn = document.getElementById("refreshBtn");
const timerBar = document.getElementById("timerBar");
const timerText = document.getElementById("timerText");
const copiedToast = document.getElementById("copiedToast");
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
    case "linux": return "keyring";
    default:      return "OS keychain";
  }
}

function linuxKeyringHint() {
  return "Install gnome-keyring, kwallet, or enable KeePassXC Secret Service plugin, then restart Firefox.";
}

function validateBase32(str) {
  const cleaned = str.replace(/[\s-]/g, "");
  if (cleaned.length === 0) return { valid: false, reason: "empty" };
  const validChars = /^[A-Z2-7]+=*$/i;
  if (!validChars.test(cleaned)) {
    for (let i = 0; i < cleaned.length; i++) {
      const c = cleaned[i];
      if (!/^[A-Z2-7=]$/i.test(c)) {
        return { valid: false, reason: `invalid character at position ${i + 1}: '${c}'` };
      }
      if (c === '=' && i < cleaned.length - 6) {
        return { valid: false, reason: `padding '=' at position ${i + 1} before end` };
      }
    }
  }
  return { valid: true };
}

// --- TOTP handling ---

async function fetchTOTP() {
  try {
    const result = await browser.runtime.sendMessage({ type: "request_totp" });
    currentCode = result.code || result;
    totpCodeEl.textContent = currentCode;
    startCountdown(result.expires_in || 30);
    return true;
  } catch (e) {
    console.error("TOTP fetch error:", e);
    return false;
  }
}

function startCountdown(seconds) {
  if (countdownInterval) clearInterval(countdownInterval);

  const total = Math.max(1, seconds);
  let remaining = total;

  function tick() {
    remaining = Math.max(0, remaining - 1);
    timerBar.style.width = (remaining / total) * 100 + "%";
    timerText.textContent = remaining + "s";
    if (remaining <= 0) {
      clearInterval(countdownInterval);
      countdownInterval = null;
      fetchTOTP();
    }
  }

  timerBar.style.width = "100%";
  timerText.textContent = seconds + "s";
  countdownInterval = setInterval(tick, 1000);
}

function stopCountdown() {
  if (countdownInterval) {
    clearInterval(countdownInterval);
    countdownInterval = null;
  }
  timerBar.style.width = "0%";
  timerText.textContent = "";
}

// --- Copy ---

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

// --- Refresh ---

refreshBtn.addEventListener("click", () => {
  stopCountdown();
  fetchTOTP();
});

// --- Seed input ---

seedInput.addEventListener("input", () => {
  saveBtn.disabled = !validateBase32(seedInput.value.trim()).valid;
});

// --- Save ---

saveBtn.addEventListener("click", async () => {
  const seed = seedInput.value.trim();
  const check = validateBase32(seed);
  if (!check.valid) {
    setStatus("Invalid base32 key: " + check.reason, "error");
    return;
  }
  saveBtn.disabled = true;
  saveBtn.textContent = "Saving...";
  try {
    const result = await browser.runtime.sendMessage({ type: "store_seed", seed });
    if (result.success) {
      setStatus("Saved successfully!", "ok");
      showDashboard();
    } else {
      const msg = currentOS === "linux" ? linuxKeyringHint() : result.message || "Unknown";
      setStatus(msg, "error");
      saveBtn.disabled = false;
      saveBtn.textContent = "Save to Keychain";
    }
  } catch (e) {
    const msg = currentOS === "linux" ? linuxKeyringHint() : "Error: " + e.message;
    setStatus(msg, "error");
    saveBtn.disabled = false;
    saveBtn.textContent = "Save to Keychain";
  }
});

// --- Delete ---

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
  confirmYesBtn.textContent = "Removing...";
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
    setStatus("Error: " + e.message, "error");
  }
  confirmYesBtn.disabled = false;
  confirmYesBtn.textContent = "Yes, Remove";
});

// --- View switching ---

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

// --- Init ---

async function init() {
  const info = await browser.runtime.getPlatformInfo();
  currentOS = info.os;
  document.getElementById("keychainName").textContent = getKeychainName(info.os);
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
    const msg = currentOS === "linux" ? linuxKeyringHint() : "Native host not responding: " + e.message;
    setStatus(msg, "error");
  }
}

init();
