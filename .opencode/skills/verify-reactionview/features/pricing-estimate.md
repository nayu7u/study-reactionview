# Pricing estimate

Pricing recomputes the estimate on the server for every choice, and each choice costs one slots request without reloading the document.

## Sub-features

- `pricing-plan` switches Team to Business and updates the total and the plan description with 1 slots request.
- `pricing-seats` increments seats from 5 to 6 with 1 slots request.
- `pricing-annual` shows the annual discount line and updates the total with 1 slots request.
- `pricing-support` shows the support fee line and updates the total with 1 slots request.
- `pricing-no-reload` keeps the document marker and the `/pricing` URL across all four choices.

## How to get to it (user POV)

- Open `/pricing`.
- Choose `Business` in the plan grid.
- Choose `＋` in `席数`.
- Choose `年払い`.
- Choose `優先サポート +¥10,000/月`.
- Read the estimate lines and the total after each choice.

## Driving it with bin/verify-reactionview

Preconditions:

- `bin/verify-reactionview doctor` prints `OK`.
- The page starts with `plan: team`, `seats: 5`, monthly billing, no support, and a `¥13,200` total.

- **Switch the plan.** Run `bin/verify-reactionview run --feature pricing-estimate`. The run clicks `button[data-herb-set='plan=business']`, waits for `.plan-description` to start with `Business`, and asserts the slots count moved by exactly 1. The total reads `¥22,000`.
- **Increase seats.** The run clicks `button[data-herb-increment='seats']`, waits for `.qty-value` to read `6` and the summary note to read `現在 6 席`, and asserts 1 slots request. The total reads `¥26,400`.
- **Enable annual billing.** The run clicks `button[data-herb-set='annual=true']`, waits for `.price-line-annual[data-active="true"]` to be displayed, and asserts 1 slots request. The total reads `¥269,280`.
- **Enable support.** The run clicks `button[data-herb-set='support=true']`, waits for `.price-line-support[data-active="true"]` and its `¥10,000` fee line, and asserts 1 slots request. The total reads `¥381,480`.
- **Confirm the page never reloaded.** `window.__verifyDocumentMarker` still reads `kept`, and `slots.urls` lists four `/pricing?format=slots` requests.
- **Capture proof.** The run writes `pricing-estimate.png` and `pricing-estimate.html` under `tmp/verify-reactionview/<run-id>/`.

## Gotchas

- Each choice costs one request only while the amounts stay outside the state branches. A server read inside a branch schedules a branch refetch, so the same switch costs two.
- Use the literal set buttons for annual and support. A `checked` binding writes the state on both `input` and `change`, and a checkbox costs two requests when the branch flips.
- Seats, annual, and support all carry `$refresh` because their steering conditions never flip (`seats > 0`, `annual == true || annual == false`, `support == true || support == false`). Removing an always-true steering condition drops the state from `Herb-State` and leaves the total stale.
- The slots counter resets on a document load. The document marker and the unchanged URL separate a slots request from a reload.
- The totals here come from the controller constants and the default states, not from a seed. Keep the monotonic trail assertion in the run, and update these numbers when the pricing rules change.
