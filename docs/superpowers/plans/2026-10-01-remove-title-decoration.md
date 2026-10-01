# Remove Title Decoration Implementation Plan

**Goal:** Remove decorative icons to the left of headings, as explicitly selected by the user; reclaim the icon gutter.

**Architecture:** Remove icon containers and their adjacent spacers from existing heading rows. Retain text, trailing controls and existing styles. Navigation, record/category/person identity icons, field icons, action buttons, state indicators and illustrations above empty-state headings are outside this selection.

**Tech Stack:** Flutter / existing widget tests.

- [x] Remove heading decorations in create/edit ledger, edit transaction, invite headers and delete/leave confirmation.
- [x] Remove heading decorations in bookkeeping/statistics ledger controls, authentication welcome and conflict introduction.
- [x] Remove only obsolete icon arguments and local variables.
- [x] Run existing layout and interaction tests, static analysis and build; independently review the diff.
- [x] Merge into master, restart preview and inspect the create-ledger sheet.

No new behavior is added. Existing interaction tests and visual checks verify this reversible presentation change; no implementation-mirroring tests are added.

## Verification

- Full suite: 333 tests passed after updating the obsolete header-icon color assertions; save-button income/expense color checks remain.
- Static analysis: no issues found.
- Independent review: addressed the missed three authentication welcome explanation decorations; latest diff approved.
- Mobile bookkeeping and edit screenshots inspected at 390px; title gutters removed with text/control alignment preserved.
- Web release build with local assets and API 18080: succeeded.

## Delivery

- af813a9 fast-forward merged into master.
- Preview restarted at http://127.0.0.1:5317/; create-ledger heading visibly has no decorative icon or icon gutter.
- Preview and API health both returned HTTP 200.
- Screenshot: D:/workplace/projects/simon-ledger/.tmp/ux-title-removal/create-ledger-master.jpg.
