# Security

This plugin runs unsandboxed QML inside the Omarchy shell process, so its footprint is
kept deliberately small:

- Network access is read-only `curl` GETs to two keyless public APIs
  (`api.jolpi.ca`, `api.openf1.org`). No tokens, no accounts, nothing sent.
- No file writes outside Quickshell's own state handling.
- No shell command execution beyond `curl`.

Report anything that looks off: open a GitHub issue or email jeremy@intentsolutions.io.
