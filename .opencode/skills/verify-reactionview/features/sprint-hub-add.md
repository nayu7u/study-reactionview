# Sprint Hub optimistic add

Adding a task from the Sprint Hub drawer inserts the row before the server confirms it, sends the create through the slots endpoint, and leaves the hero count to a later refetch.

## Sub-features

- `add-open-drawer` opens the creation drawer and sends one slots request for the branch.
- `add-optimistic-row` inserts the new row before the create response lands.
- `add-post-201` sends `POST /tasks?format=slots` and splices the returned row.
- `add-drawer-close-refetch` sends a GET when the drawer closes; under an active search it can remove the optimistic row.
- `add-sync-hero` uses `🔄 同期` to refetch the filtered list and move the hero from 10 to 11.

## How to get to it (user POV)

- Open `/`.
- Search for `quick start` so the list has one row.
- Choose `＋ 新規タスク`.
- Type a title in `タイトル`.
- Choose `追加`.
- Choose `🔄 同期`.

## Driving it with bin/verify-reactionview

Preconditions:

- `bin/verify-reactionview doctor` prints `OK`.
- The disposable database has 10 tasks and no row titled `verify probe`.
- The page starts at `/` with 10 rows.
- The search field is empty.

- **Narrow the list.** Run `bin/verify-reactionview run --feature sprint-hub-add`. The run types `quick start` and waits for one row. `result.json` records the search slots count.
- **Open the drawer.** The run clicks `＋ 新規タスク` and waits for `.drawer`. The branch flip sends at least one slots request.
- **Add the task.** The run fills `input#task_title` with `verify probe <run-id>`, waits for the `追加` button to enable, and clicks it.
- **Capture the optimistic row.** The run polls `.task-list .task-item` every 50ms. When two rows appear, it writes `sprint-hub-add-optimistic.json` with both row texts and the hero before and after, then takes `sprint-hub-add-optimistic.png`. The JSON is the reliable proof because the drawer-close refetch can remove the row before a later screenshot.
- **Confirm the create.** `result.json` shows a slots URL containing `/tasks?format=slots`. The optimistic row text contains the generated title.
- **Sync.** The run clicks `🔄 同期`, waits for the hero to contain `11`, and waits for the filtered list to return to one row. The final `sprint-hub-add.png` shows the synced state.

## Gotchas

- Opening the drawer costs one slots request. Closing it after submit can cost another, and that refetch can remove the optimistic row while the search filter is active. Read the optimistic JSON, not only the final screenshot.
- The 201 splice does not update the hero. A later GET can update it, so `hero_after_add` may be 10 or 11 depending on when the drawer-close refetch lands. Do not use the hero as the only optimistic proof.
- The added row is spliced into the filtered list even though it does not match the query. Sync restores the filtered result.
- The create button stays disabled until the title is non-empty. Wait for `enabled?` before clicking.
- The window for the optimistic row is short. Use `--keep` if you need the disposable database to inspect the failed state, then clean it up.
