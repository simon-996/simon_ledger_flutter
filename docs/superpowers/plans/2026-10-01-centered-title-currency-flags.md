# Centered Ledger Title and Currency Flags

**Goal:** Center the ledger detail name in the screen and add a shared flag to currency choices.
**Architecture:** Reserve equal toolbar space on both sides through loading/data states. Use a shared currency metadata map and flag/label widgets, retaining text codes/names and selected state. Image flags from country_flags use local package assets; EUR maps explicitly to EU, HKD/MOP/TWD to their regions; unknown codes use a neutral currency icon.
**Tech Stack:** Flutter, country_flags 4.1.2, existing widget tests.

- [x] Reproduce long-title offset at mobile width using the application theme; verify center after correction.
- [x] Add shared currency presentation and wire ledger dropdown, single/quick/search transaction selectors, dashboard/statistics currency switches.
- [x] Verify known/unknown codes, selection/search and narrow layouts; run full tests, analyze, build and review.
- [ ] Merge master and restart preview; inspect changed controls.

User explicitly requested both corrections. Flags are identity markers in currency controls, not heading decoration.

## Verification

- Original long-title regression: title center x=175 vs screen center x=195 at 390px; passes after symmetrical toolbar reservations.
- Original single-currency flag test failed because no flag existed; passes after shared component integration.
- Compact multi-currency picker test passed after responsive search fallback.
- Relevant tests: 18 passed. Full suite: 336 passed.
- Static analysis: no issues found.
- Independent review: no blocking findings; package flag mappings and local assets checked.
- Bookkeeping normal/1.5 scale and AI review screenshots inspected at 390px: visible flags and readable currency labels.
- Source package: https://pub.dev/packages/country_flags (MIT; local SVG-derived image assets).
- Web release build: succeeded.
