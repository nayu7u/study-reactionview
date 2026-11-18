# Sprint Hub search

Search on Sprint Hub sends the query to the server and replaces the keyed task rows with the matching result. The input writes the client `query` state; the controller reads it through `herb_state` after a 220ms debounce.

## Sub-features

- `search-filter` narrows the 10 seeded tasks to the one row matching `quick start`.
- `search-slots` sends a `GET /?format=slots` for the debounced query.
- `search-clear` resets the query text and the toolbar note, but does not refetch the rows in this build.

## How to get to it (user POV)

- Open `/`.
- Type `quick start` in the `タスクを検索` field.
- Choose `クリア` to empty the field.
- Choose `🔄 同期` to refetch the current state.

## Driving it with bin/verify-reactionview

Preconditions:

- `bin/verify-reactionview doctor` prints `OK`.
- The disposable database seed has 10 tasks and no row titled `verify probe`.
- The page starts at `/` with 10 `.task-list .task-item` rows.

- **Filter the list.** Run `bin/verify-reactionview run --feature sprint-hub-search`. The run types `quick start` into `input[name="search"]`, waits for one row, and reads `result.json`. `slots.count` is at least `1`, and `slots.urls` contains `/?format=slots`.
- **Confirm the row.** The one row contains `Read the ReActionView quick start`, and `.toolbar-note` contains `の結果`.
- **Capture proof.** The run writes `sprint-hub-search.png` and `sprint-hub-search.html` under `tmp/verify-reactionview/<run-id>/`.
- **Clear the field manually.** Choose `クリア`. The input becomes empty and the note reads `全件表示`, but the row count stays at 1 and no slots request is sent. This is the measured gap, not a passing clear.
- **Restore all rows.** Choose `🔄 同期` or reload the page. The list returns to 10 rows and the hero still reads 10 tasks.

## Gotchas

- The debounce is 220ms. Type the whole query, then wait for the row count to settle before reading the count.
- The slots counter is per page load. Do not compare a count from a reloaded page with the prior count.
- A passing screenshot alone does not prove the clear behavior. Read `slots.count` and the row count.
- Search is server-mode. The client state only steers the request; the filtered rows come from the slots response.
- The clear button is a known gap in this build. Do not weaken the journey to make it look like a refetch.
