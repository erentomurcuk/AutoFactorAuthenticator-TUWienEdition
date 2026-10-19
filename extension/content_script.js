const TOTP_WINDOW_SECONDS = 30;

// Field detection with fallbacks. The IdP names its field #totp today; the
// other two match what the platform itself declares and what a renamed field
// would most plausibly be called, so a TU Wien IdP update can no longer kill
// auto-fill silently. First visible candidate wins.
const FIELD_SELECTORS = [
  "#totp",
  'input[autocomplete="one-time-code"]',
  'input[name*="totp" i]',
];

function isVisibleTextInput(el) {
  if (!(el instanceof HTMLInputElement)) return false;
  const allowedTypes = ["text", "tel", "password", "number", ""];
  if (!allowedTypes.includes(el.type)) return false;
  if (el.disabled || el.readOnly) return false;
  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;
  return true;
}

function currentTOTPCounter() {
  return Math.floor(Date.now() / 1000 / TOTP_WINDOW_SECONDS);
}

function findTOTPField() {
  for (const sel of FIELD_SELECTORS) {
    for (const el of document.querySelectorAll(sel)) {
      if (isVisibleTextInput(el)) return el;
    }
  }
  return null;
}

function fillTOTP() {
  const field = findTOTPField();
  if (!field) return;

  // Re-fill whenever the TOTP window has advanced since we last filled this
  // element. Avoids the "autofilled once, never again" problem when the
  // same input is reused after a wrong submission.
  const lastCounter = Number(field.dataset.autotissAutofilledCounter || -1);
  const now = currentTOTPCounter();
  if (field.dataset.autotissAutofilled === "true" && lastCounter === now) return;

  field.dataset.autotissAutofilled = "true";
  field.dataset.autotissAutofilledCounter = String(now);

  browser.runtime.sendMessage({ type: "request_totp" }).then((res) => {
    if (!res || typeof res.code !== "string") {
      throw new Error("bad response");
    }
    field.value = res.code;
    field.dispatchEvent(new Event("input", { bubbles: true }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
  }).catch(() => {
    // Allow a retry on the next tick / DOM change.
    delete field.dataset.autotissAutofilled;
    delete field.dataset.autotissAutofilledCounter;
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

if (findTOTPField()) {
  fillTOTP();
}

if (document.body) {
  new MutationObserver(onDomChange).observe(document.body, { childList: true, subtree: true });
}