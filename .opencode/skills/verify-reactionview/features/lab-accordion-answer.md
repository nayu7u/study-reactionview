# Lab accordion answer

The Client Lab FAQ keeps each answer outside the per-item branch and toggles it with a `hidden` presence binding.

## Sub-features

- `accordion-open` shows the answer and switches the marker to `－`.
- `accordion-close` hides the answer and returns the marker to `＋`.
- `accordion-zero-slots` keeps both actions at zero slots requests.

## How to get to it (user POV)

- Open `/lab`.
- Scroll to the FAQ section.
- Choose the first question.
- Read the answer, then choose the question again.

## Driving it with bin/verify-reactionview

Preconditions:

- `bin/verify-reactionview doctor` prints `OK`.
- `/lab` renders three `.acc-head` buttons and three `.acc-body` elements.

- **Open the row.** Run `bin/verify-reactionview run --feature lab-accordion-answer`. The run clicks the first `.acc-head`.
- **Confirm the answer.** The first `.acc-body` is displayed and contains `要りません`.
- **Confirm the marker.** The first `.acc-marker` reads `－`.
- **Close the row.** The run clicks the same header again. The body is hidden and the marker reads `＋`.
- **Confirm zero slots.** `result.json` has `slots.count` `0` and an empty `slots.urls`.
- **Capture proof.** The run writes `lab-accordion-open.png`, `lab-accordion-answer.png`, and `lab-accordion-answer.html` under `tmp/verify-reactionview/<run-id>/`.

## Gotchas

- The answer already sits outside the branch. Do not move it inside a per-item arm; server-read values are dropped there (0.6.0 and 0.6.1).
- The marker is static branch text. It materializes because the full-page region is parked; a partial arm would not.
- The page is client mode. A slots request on open or close is a regression.
