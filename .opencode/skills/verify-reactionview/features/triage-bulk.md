# Triage bulk selection

Triage lets a user select task rows, see the selected count without a server round trip, and update only those rows through a standard PATCH form.

## Sub-features

- `triage-select` checks two rows and moves `selected_count` to `2` with 0 slots requests.
- `triage-standard-form` submits the selected ids through `PATCH /triage` as a standard form navigation, not a slots request.
- `triage-priority` updates the selected rows' priority and leaves the unselected rows alone.
- `triage-no-select-all` records that per-item state cannot be written from a global select-all button.

## How to get to it (user POV)

- Open `/triage`.
- Choose the checkbox on two task rows.
- Choose a priority from `優先度`.
- Choose `選択したタスクを更新`.
- Read the flash and the priority badges on the same rows.

## Driving it with bin/verify-reactionview

Preconditions:

- `bin/verify-reactionview doctor` prints `OK`.
- The disposable seed has 10 tasks with the first row `高` and the second row `中`.
- The page starts at `/triage` with 10 `.triage-row` elements.

- **Select rows.** Run `bin/verify-reactionview run --feature triage-bulk`. The run clicks the first two `.triage-check` labels and waits for `.triage-count` to read `2`.
- **Confirm client-only selection.** Before submitting, `slots.count` stays at `0`, and `slots.urls` is empty.
- **Choose the target.** The run selects `1` (`低`) in `select#triage_priority`.
- **Submit.** The run clicks `選択したタスクを更新` and waits for the flash `2件の優先度を更新しました`.
- **Confirm the update.** The first two `.triage-row .prio` badges read `低`, the third remains `中`, and the page reloads with `selected_count` back at `0`.
- **Capture proof.** The run writes `triage-bulk-selected.png`, `triage-bulk.png`, and `triage-bulk.html` under `tmp/verify-reactionview/<run-id>/`.

## Gotchas

- The count fold must be read after the list. Moving the count above the loop produces a "read before its count is complete" compile error.
- The bulk update is a document navigation, not a slots request. The counter is per document, so the post-redirect `slots.count` of `0` describes the new page, not the submit; read the row priorities and the flash as the submit's proof.
- There is no select-all. `selected` is a per-item state, and a button outside the loop cannot write every instance.
- The screen mutates `Task.priority`. The disposable database is thrown away; in dev, run `bin/rails db:seed` to restore the seed priorities.
- no-JS can check and submit, but the count display stays at its initial `0`. Do not report the count as a no-JS behavior.
