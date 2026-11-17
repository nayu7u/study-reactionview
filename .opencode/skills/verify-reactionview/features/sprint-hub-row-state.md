# Sprint Hub row state

Done and pin are browser-owned row states. Their visual change and their fold counts must follow without a slots request.

## Sub-features

- `row-done` toggles the first row's done state and moves the done count to `1/10`.
- `row-pin` toggles the star and moves the pin count to `1`.
- `row-zero-slots` keeps both interactions at zero slots requests.
- `row-independent` keeps done and pin counts independent.

## How to get to it (user POV)

- Open `/`.
- Choose the checkbox or row label on the first task.
- Choose the star on the first task.
- Read `N/M 件完了` and `N 件ピン留め` below the list.

## Driving it with bin/verify-reactionview

Preconditions:

- `bin/verify-reactionview doctor` prints `OK`.
- The seed has 10 tasks and no done or pinned rows.
- The page starts at `/` with 10 `.task-list .task-item` rows.

- **Toggle done.** Run `bin/verify-reactionview run --feature sprint-hub-row-state`. The run clicks the first `.task-check` label and waits for `.task-stat` to start with `1/10`.
- **Toggle pin.** The run clicks the first `.task-pin` label and waits for `.pin-stat` to contain `1`.
- **Confirm zero slots.** `result.json` has `slots.count` equal to the baseline and an empty `slots.urls`.
- **Capture proof.** The run writes `sprint-hub-row-state.png` and `.html` under `tmp/verify-reactionview/<run-id>/`. The screenshot shows the checked row, the filled star, and both counts.

## Gotchas

- Click the `.task-check` or `.task-pin` label, not the hidden checkbox input. Selenium cannot reliably click an invisible input.
- The done styling uses `:has(input:checked)`. Assert the visible state and the count, not a class interpolation.
- Pin and done are independent. Toggling one must not move the other count.
- Row state is client-owned and resets on reload. Do not expect the seed or the disposable database to retain it.
- A nonzero slots count means the interaction fell back to the server. Treat it as `NOT VERIFIED`, not as a slower pass.
