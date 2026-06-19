function fillTOTP() {
  const field = document.getElementById("totp");
  if (!field || field.dataset.tuwelAutofilled) return;
  field.dataset.tuwelAutofilled = "true";
  browser.runtime.sendMessage({ type: "request_totp" }).then((code) => {
    field.value = code;
    field.dispatchEvent(new Event("input", { bubbles: true }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
  }).catch(() => {
    delete field.dataset.tuwelAutofilled;
  });
}

if (document.getElementById("totp")) {
  fillTOTP();
}

new MutationObserver(() => {
  fillTOTP();
}).observe(document.body, { childList: true, subtree: true });
