# Verification

## What is tested

- **Unit and integration (26 tests, CI-gated):** `Model.js` pure functions.
  Schedule parsing, countdown, live-window detection, leaderboard joins, gap
  formatting, the safety-car and flag fold, and the input sanitizer, all run
  against real captured jolpica and openf1 responses under `tests/fixtures/`.
- **Static (CI-gated):** `node --check` on every JS file, manifest schema +
  namespaced-id assertions, no-symlink check. `qmllint` runs clean (exit 0,
  0 errors) against the QML with the Quattro shell import paths; its warning
  profile matches the first-party plugins.
- **Full-stack render (rig):** the plugin runs in the real Omarchy Quattro
  shell (Quickshell + headless Hyprland/sway) and makes its **own** real
  network calls. Verified end-to-end against the real Hungarian GP race data.
  Live leaderboard, gaps, flag status, weekend schedule, and both championship
  tables all render correctly. Screenshot: `preview.png`.
- **Acceptance:** `omarchy-plugin-validate` passes.

## Live-data end-to-end soak, scheduled

The one path a captured fixture cannot fully exercise is the countdown→live
transition against a **currently-running** F1 session on an unfaked clock.
That soak is scheduled for **Dutch Grand Prix FP1, Friday 2026-08-21 10:30 UTC**:
the widget (real system clock) is expected to flip the pill from the countdown
to live timing as the session starts, tick the leaderboard, and reflect any
flag/safety-car status. This file is updated with the result and evidence
after that run.
