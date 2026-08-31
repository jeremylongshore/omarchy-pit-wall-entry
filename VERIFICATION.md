# Verification record

## Current local evidence

- `npm test`: 52/52 passing; 100% statements, lines, and functions; 95.05%
  branches over the complete pure `Model.js` layer and repository contracts.
- `npm run test:race`: three consecutive clean repetitions.
- `npm run test:mutation`: 90.37%; 758 killed, 2 timeout, 81 survived, against
  a blocking 90% floor.
- `npm run audit:deps`: zero known npm vulnerabilities.
- ShellCheck: clean across developer, E2E, gate, and pre-push scripts.
- Vendored Omarchy gates: C28-C42 pass, including panel design, QML safety,
  runtime dependencies, SSRF, local state, and resource budgets.
- Marketplace contract: both descriptions are identical and exactly 500
  characters; the Formula 1 banner is product-specific.

Fixtures are bounded captures from Jolpica and OpenF1. Tests cover schedule and
session parsing, all session labels and durations, exact live-window boundaries,
countdowns, driver and constructor standings, live event merging, leaderboard
gaps, track flags and safety-car state, team livery hues, and every supported FIA
country code.

## Historical rig evidence

An earlier revision rendered in the Omarchy Quattro shell using real Hungarian
Grand Prix data. It showed the live leaderboard, gaps, flag state, weekend
schedule, and both championship tables. That result established the product
shape but does not prove the current candidate tree.

## Current-revision boundary

The current QML source, exact 1280x720 screenshot, clean shell log, and human
marketplace-scale inspection still require Buzz production. The old 1320x700
preview remains useful as visual history but is not accepted as current proof.
C43 intentionally blocks shipment until `.rig-proof.json` and
`.render-proof.json` bind the evidence to the exact candidate tree. After push,
the listed plugin also requires a new marketplace Verify request for that final
SHA.
