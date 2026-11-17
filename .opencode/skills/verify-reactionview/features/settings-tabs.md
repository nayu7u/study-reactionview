# Settings tabs

Settings is a client-mode screen. Profile, Notifications, and Billing must switch without a slots request, with exactly one panel visible at a time.

## Sub-features

- `tab-profile` opens the Profile panel with the display-name, email, bio, and public-profile fields.
- `tab-notifications` opens the Notifications panel with digest and frequency controls.
- `tab-billing` opens the Billing panel with plan and annual controls.
- `tab-zero-slots` keeps every tab switch at zero slots requests.
- `tab-single-panel` keeps exactly one `.settings-tab-panel` displayed.

## How to get to it (user POV)

- Open `/settings`.
- Choose `Profile`, `Notifications`, or `Billing` in the `設定` navigation.
- Read the panel that appears under the navigation.

## Driving it with bin/verify-reactionview

Preconditions:

- `bin/verify-reactionview doctor` prints `OK`.
- The Settings page loads with Profile active and no dirty state.
- The page starts at `/settings` with three `.settings-nav button` controls.

- **Cycle the tabs.** Run `bin/verify-reactionview run --feature settings-tabs`. The run clicks Notifications, Billing, and Profile in that order.
- **Confirm the active tab.** After each click, the button with `aria-pressed="true"` matches the clicked label, and exactly one `.settings-tab-panel` is displayed.
- **Confirm zero slots.** `result.json` has `slots.count` equal to the baseline and an empty `slots.urls`.
- **Capture proof.** The run writes `settings-tabs-notifications.png`, `settings-tabs-billing.png`, `settings-tabs-profile.png`, and the final `.html` under `tmp/verify-reactionview/<run-id>/`.

## Gotchas

- The inactive panels use the `hidden` attribute, not removal from the DOM. Count displayed panels, not panels in the HTML.
- The tab switch is inside the panel wrapper's dirty tracking only if it changes an input. Tab switches must not set `dirty` or enable Save.
- The screen is client mode. A slots request on a tab click is a regression.
- The test environment disables CSRF. This journey proves client state only; it does not prove authorization or persistence.
- Run the tab cycle from a fresh page load. A prior failed run can leave a different tab active in the browser, but the next navigation resets it.
