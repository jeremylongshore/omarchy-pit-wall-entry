# Testing posture

Seven-layer map for this repo (Intent Solutions taxonomy):

| Layer | Status | Where |
| --- | --- | --- |
| L1 git hooks | — (repo too small to gate locally; CI is the gate) | |
| L2 static | qmllint-clean QML; shellcheck-clean scripts | manual pre-release |
| L3 unit | **20 tests** over the pure `Model.js` data layer | `tests/model.test.js` |
| L4 integration | fixtures are real captured API responses, parsed end-to-end | `tests/fixtures/` |
| L5 system | full render on a headless Quattro shell rig (Hyprland/sway + quickshell) | rig screenshots in `assets/` + `preview.png` |
| L6 E2E | live-mode rehearsal via `debugTimeOffsetMs`; real-session soak during race weekends | manual |
| L7 acceptance | `omarchy-plugin-validate` (upstream schema gate) green | pre-submission |

CI runs L3/L4 on every push (`.github/workflows/test.yml`). The QML layer is
deliberately thin — every branch that can be wrong lives in `Model.js` where node can
reach it.
