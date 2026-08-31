# Testing posture

| Layer | Command | Current evidence |
| --- | --- | --- |
| Static contract | `npm test` | Exact copy, banner semantics, pinned CI, conflict scan, render-proof contract |
| Unit and fixture integration | `npm test` | 52 tests; 100% statements, lines, functions; 95.05% branches |
| Race repetition | `npm run test:race` | Three clean repetitions |
| Mutation | `npm run test:mutation` | 90.37%; blocking floor 90% |
| Dependency | `npm run audit:deps` | Zero known npm vulnerabilities |
| Repository integrity | `npm run audit` | Hash verification, deep audit, scan |
| Omarchy policy | `scripts/run-plugin-gates.sh .` | C28-C42 pass; C43 awaits current Buzz proof |
| Production E2E | `npm run test:e2e` | Must execute on Buzz against the exact candidate tree |

GitHub Actions uses commit-pinned actions and runs dependency, unit/coverage,
race, mutation, audit, and ShellCheck gates. CI does not call Jolpica or OpenF1.

Node tests prove the pure data model and repository contracts. They cannot prove
QML imports, popup geometry, live shell wiring, or marketplace readability.
Those require the current-revision Buzz run, clean shell log, exact 1280x720
preview, and explicit human approval.
