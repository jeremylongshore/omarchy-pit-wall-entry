# Contributing

Issues and PRs welcome.

- The data layer is `Model.js`, pure functions, no QML or network. Every change to it
  needs a test in `tests/model.test.js` (`node --test tests/*.test.js`).
- QML follows the Omarchy Quattro first-party conventions: theme tokens only (no
  hardcoded colors), `setting()` for config, `Process`+`StdioCollector` for network.
- Fixtures under `tests/fixtures/` are real captured API responses. If an API shape
  changes, re-capture rather than hand-editing.
