# Changelog

Notable changes to Pit Wall.

Entries are derived from this repository's commit history, so every line
corresponds to a real change. The format follows Keep a Changelog and the
project uses Semantic Versioning.

Regenerate with `scripts/gen-changelog.sh`.

## [Unreleased]

Nothing yet.

## [1.0.0] - 2026-08-22

### Security

- Apply the four-reviewer panel findings: correctness, security, taste
- Bound every unbounded Text so long API data cannot clip the row

### Added

- Pit Wall v1.0.0: F1 race weekend widget for the Omarchy bar
- Lead the bar pill with the checkered-flag glyph
- Rig-verified live mode, preview assets, banner, governance docs
- Safety car and flag status on the live pill; real static gates in CI
- Colour the championship tables by team, not by nothing
- Add country codes, the next rounds, and where the data came from

### Fixed

- Route the banner racing line below the text, not through it
- Drop the stray leading pill space and correct the glyph doc drift
- Middots for em dashes in the three rendered tooltip strings

### Internal

Tooling and repository changes with no effect on the shipped plugin.

- File the seven-layer testing posture
- Rewrite taglines in plain English
- Record the honest E2E posture and the scheduled live-data soak
- Strip em dashes from all repo prose, rewrite in plain voice
- State exactly where Pit Wall pulls data
- Vendor c40, the panel design gate, and repair the sync that dropped it
- Vendor rig-render, which loads the plugin into a real shell
- Add four-lane MiniMax review and backfill the changelog

