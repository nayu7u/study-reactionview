# UI Field over-limit warning

The UI Kit field shows its 60-character warning through a `hidden` presence binding, so crossing the limit stays in the browser.

## Sub-features

- `field-warning-show` types 61 characters and reveals `.ui-field-over`.
- `field-warning-hide` deletes one character and hides it again.
- `field-warning-zero-slots` keeps both changes at zero slots requests.

## How to get to it (user POV)

- Open `/ui`.
- Find the Field card labeled 自己紹介 (the textarea whose hint reads N/60字).
- Type 61 characters.
- Read the warning after the character count, then delete one character.

## Driving it with bin/verify-reactionview

Preconditions:

- `bin/verify-reactionview doctor` prints `OK`.
- `/ui` renders one `textarea.ui-field` and the hidden `.ui-field-over` span.

- **Cross the limit.** Run `bin/verify-reactionview run --feature ui-field-warning`. The run types 61 `a` characters.
- **Confirm the warning.** `.ui-field-over` is displayed and contains `長すぎます`.
- **Return under the limit.** The run sends Backspace once. The warning is hidden again.
- **Confirm zero slots.** `result.json` has `slots.count` `0` and an empty `slots.urls`.
- **Capture proof.** The run writes `ui-field-warning-over.png`, `ui-field-warning.png`, and `ui-field-warning.html` under `tmp/verify-reactionview/<run-id>/`.

## Gotchas

- The warning is always in the DOM. Assert `displayed?`, not presence.
- The old branch implementation dropped the warning from the DOM because partial arms are not parked (0.6.0 and 0.6.1).
- The field is client mode. A slots request on either keystroke crossing is a regression.
