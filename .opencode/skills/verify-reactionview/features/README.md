# Verification map

This directory is the maintained source for verifying the user-facing behavior of Study ReActionView. Read this index before driving the app, then use the matching feature file as the recipe.

The map covers the six journeys that `bin/verify-reactionview` drives. The other screens (`/patterns`, `/lab`, `/ui`, `/dashboard`, `/forms`, `/catalog`, `/apply`, `/outbox`, `/thread`, `/tree`) are outside this harness; verify them with their docs and one-off probes, and do not report this run as covering them.

## Baseline preconditions

- Run from the repository root.
- `bin/verify-reactionview doctor` prints `OK`.
- The bundle is installed, and `bin/rails` boots.
- Chrome for Testing is available through Selenium Manager, with the Chrome runtime libraries installed.
- The harness uses `RAILS_ENV=test` and a disposable SQLite database under `tmp/verify-reactionview/<run-id>/`.
- The seed creates 10 tasks, 3 proposals, 12 talks, 3 submissions, 3 posts, and a 4-level tree.
- Triage starts with the same 10 tasks; its bulk update mutates priority and is reset by the disposable database.
- Pricing starts with team, 5 seats, monthly billing, no support, and a `¥13,200` total.
- The server listens on `127.0.0.1:3310` or the next free port.
- Never drive an instance that this run did not start.

## Driving conventions

- Start every feature from the baseline page load unless its preconditions say otherwise.
- Prefer the stable selectors in the feature file over DOM position.
- Treat every command as literal.
- Run the browser through `bin/verify-reactionview`; do not attach to a dev server by hand.
- Read `result.json` before trusting a screenshot. A screenshot proves the final screen, not the intermediate action.
- Keep evidence for a feature together with the feature ID and run ID.
- Report an unreachable path with the command and the unmet precondition.
- Do not report a skipped feature as verified through a different path.

## Proof and skip reporting

- A feature is `VERIFIED` only when every assertion in its recipe passes.
- `NOT VERIFIED` includes the error, a failure screenshot, and a failure DOM.
- Slots counts are recorded per page load. The harness records the count and URLs, not just a pass.
- Mutation proof includes the row snapshot and the final screen.
- Settings proofs include one screenshot per tab.
- A missing browser or boot failure is `NOT VERIFIED`, not a skip.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with bin/verify-reactionview` starts with `Preconditions:` and pairs each user action with an exact command and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

## Features

- [Sprint Hub search](sprint-hub-search.md) covers the server-filtered query and the measured clear behavior.
- [Sprint Hub row state](sprint-hub-row-state.md) covers done and pin toggles with zero slots requests.
- [Settings tabs](settings-tabs.md) covers the three client-mode panels and zero slots requests.
- [Triage bulk selection](triage-bulk.md) covers per-row selection, the count fold, and the standard bulk PATCH.
- [Sprint Hub optimistic add](sprint-hub-add.md) covers the drawer, the 201 splice, the drawer-close refetch, and sync.
- [Pricing estimate](pricing-estimate.md) covers plan, seats, annual, and support, each with exactly one slots request.
