# Testing posture

Seven-layer map for this repo (Intent Solutions taxonomy):

| Layer | Status | Where |
| --- | --- | --- |
| L1 git hooks | none (repo too small to gate locally, CI is the gate) | |
| L2 static | qmllint exit-0 (rig, shell import paths; warning profile matches first-party plugins) + JS syntax check, manifest schema check, symlink check in CI | `.github/workflows/test.yml` `static` job |
| L3 unit | **24 tests** over the pure `Model.js` data layer (incl. real Hungary-GP VSC replay for track status) | `tests/model.test.js` |
| L4 integration | fixtures are real captured API responses, parsed end-to-end | `tests/fixtures/` |
| L5 system | full render on a headless Quattro shell rig (Hyprland/sway + quickshell) | rig screenshots in `assets/` + `preview.png` |
| L6 E2E | live-mode rehearsal via `PIT_WALL_FAKE_OFFSET_MS`; real-session soak during race weekends | manual |
| L7 acceptance | `omarchy-plugin-validate` (upstream schema gate) green | pre-submission |

CI runs L3/L4 on every push (`.github/workflows/test.yml`). The QML layer is
deliberately thin, every branch that can be wrong lives in `Model.js` where node can
reach it.
