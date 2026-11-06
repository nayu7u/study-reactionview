// Why this small adapter: the outbox exposes retry/discard only as a JS API.
// The failed row renders in ERB, but acting on it needs this glue.
document.addEventListener("click", (event) => {
  const retry = event.target.closest("[data-outbox-retry]");
  if (retry) {
    event.preventDefault();
    window.HerbRuntime?.outbox?.retry(retry);
    return;
  }

  const discard = event.target.closest("[data-outbox-discard]");
  if (discard) {
    event.preventDefault();
    window.HerbRuntime?.outbox?.discard(discard);
  }
});
