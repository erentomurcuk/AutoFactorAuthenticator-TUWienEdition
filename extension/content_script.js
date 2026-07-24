const TOTP_WINDOW_SECONDS = 30;

function isVisibleTextInput(el) {
  if (!(el instanceof HTMLInputElement)) return false;
  const allowedTypes = ["text", "tel", "password", "number", ""];
  if (!allowedTypes.includes(el.type)) return false;
  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;
  return true;
}

function currentTOTPCounter() {
  return Math.floor(Date.now() / 1000 / TOTP_WINDOW_SECONDS);
}

function fillTOTP() {
  const field = document.getElementById("totp");
  if (!field || !isVisibleTextInput(field)) return;

  // Re-fill whenever the TOTP window has advanced since we last filled this
  // element. Avoids the "autofilled once, never again" problem when the
  // same #totp input is reused after a wrong submission.
  const lastCounter = Number(field.dataset.tuwienAutofilledCounter || -1);
  const now = currentTOTPCounter();
  if (field.dataset.tuwienAutofilled === "true" && lastCounter === now) return;

  field.dataset.tuwienAutofilled = "true";
  field.dataset.tuwienAutofilledCounter = String(now);

  browser.runtime.sendMessage({ type: "request_totp" }).then((res) => {
    field.value = res.code;
    field.dispatchEvent(new Event("input", { bubbles: true }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
  }).catch(() => {
    // Allow a retry on the next tick / DOM change.
    delete field.dataset.tuwienAutofilled;
    delete field.dataset.tuwienAutofilledCounter;
  });
}

let debounceTimer = null;
function onDomChange() {
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    debounceTimer = null;
    fillTOTP();
  }, 50);
}

if (document.getElementById("totp")) {
  fillTOTP();
}

if (document.body) {
  new MutationObserver(onDomChange).observe(document.body, { childList: true, subtree: true });
}