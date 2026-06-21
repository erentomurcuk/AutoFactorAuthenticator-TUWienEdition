function isVisibleTextInput(el) {
  if (!(el instanceof HTMLInputElement)) return false;
  const allowedTypes = ["text", "tel", "password", "number", ""];
  if (!allowedTypes.includes(el.type)) return false;
  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;
  return true;
}

function fillTOTP() {
  const field = document.getElementById("totp");
  if (!field || field.dataset.tuwienAutofilled) return;
  if (!isVisibleTextInput(field)) return;

  field.dataset.tuwienAutofilled = "true";
  browser.runtime.sendMessage({ type: "request_totp" }).then((code) => {
    field.value = code;
    field.dispatchEvent(new Event("input", { bubbles: true }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
  }).catch(() => {
    delete field.dataset.tuwienAutofilled;
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
