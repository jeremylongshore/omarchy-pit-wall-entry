# Marketplace contract

Pit Wall ships one `barWidget` whose public listing and runtime widget share
the same product promise.

- Both manifest descriptions are identical and exactly 500 characters.
- The copy states the countdown, live timing, panel content, refresh cadence,
  data sources, and privacy/write boundary.
- `assets/banner.svg` identifies Pit Wall and depicts Formula 1 race state.
- `preview.png` is accepted only with current-tree Buzz provenance, exact
  1280x720 dimensions, a clean shell-log hash, and explicit visual approval.
- Network traffic consists of bounded, read-only, keyless Jolpica and OpenF1
  requests. The plugin has no account, token, telemetry, or write path.

`tests/contract.test.js` and gate C43 enforce the machine-checkable portions.
