const statusEl = document.getElementById("status");
const configuredView = document.getElementById("configuredView");
const setupView = document.getElementById("setupView");
const seedInput = document.getElementById("seedInput");
const saveBtn = document.getElementById("saveBtn");
const deleteBtn = document.getElementById("deleteBtn");

function setStatus(text, type) {
  statusEl.textContent = text;
  statusEl.className = "status " + type;
}

function getKeychainName(os) {
  switch (os) {
    case "mac":  return "Apple Keychain";
    case "win":  return "Windows Credential Manager";
    case "linux": return "GNOME Keyring / KDE Wallet";
    default:     return "OS keychain";
  }
}

function isValidBase32(str) {
  return /^[A-Z2-7]+=*$/i.test(str.replace(/[\s-]/g, ""));
}

seedInput.addEventListener("input", () => {
  saveBtn.disabled = !isValidBase32(seedInput.value.trim());
});

async function init() {
  browser.runtime.getPlatformInfo().then((info) => {
    document.getElementById("keychainName").textContent = getKeychainName(info.os);
  });
  try {
    const result = await browser.runtime.sendMessage({ type: "check_configured" });
    if (result.configured) {
      setStatus("Keychain: configured", "ok");
      configuredView.classList.remove("hidden");
      setupView.classList.add("hidden");
    } else {
      setStatus("No seed configured yet", "info");
      configuredView.classList.add("hidden");
      setupView.classList.remove("hidden");
    }
  } catch (e) {
    setStatus("Native host not found. Run install.sh first.", "error");
  }
}

saveBtn.addEventListener("click", async () => {
  const seed = seedInput.value.trim();
  if (!isValidBase32(seed)) {
    setStatus("Invalid base32 key", "error");
    return;
  }
  saveBtn.disabled = true;
  saveBtn.textContent = "Saving...";
  try {
    const result = await browser.runtime.sendMessage({ type: "store_seed", seed });
    if (result.success) {
      setStatus("Saved successfully!", "ok");
      configuredView.classList.remove("hidden");
      setupView.classList.add("hidden");
    } else {
      setStatus("Error: " + (result.message || "Unknown"), "error");
      saveBtn.disabled = false;
      saveBtn.textContent = "Save to Keychain";
    }
  } catch (e) {
    setStatus("Error: " + e.message, "error");
    saveBtn.disabled = false;
    saveBtn.textContent = "Save to Keychain";
  }
});

deleteBtn.addEventListener("click", async () => {
  if (!confirm("Remove the TOTP seed from your keychain?")) return;
  deleteBtn.disabled = true;
  try {
    const result = await browser.runtime.sendMessage({ type: "delete_seed" });
    if (result.success) {
      setStatus("Seed removed", "info");
      configuredView.classList.add("hidden");
      setupView.classList.remove("hidden");
      deleteBtn.disabled = false;
    } else {
      setStatus("Error: " + (result.message || "Unknown"), "error");
      deleteBtn.disabled = false;
    }
  } catch (e) {
    setStatus("Error: " + e.message, "error");
    deleteBtn.disabled = false;
  }
});

init();
