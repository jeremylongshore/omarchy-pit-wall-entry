# Test audit

Audit date: 2026-08-30

| Layer | Status | Evidence |
| --- | --- | --- |
| Git hook | Implemented | Vendored fail-closed Omarchy lane on pre-push |
| Static | Implemented | ShellCheck, conflict scan, manifest/banner/CI contracts, C28-C42 |
| Unit | Implemented | 52 deterministic Node tests |
| Integration | Implemented | Captured Jolpica and OpenF1 payloads plus malformed and sparse shapes |
| System | Pending exact rig | Buzz QML and real-shell validation |
| E2E | Pending exact rig | Hash-bound run, shell log, and 1280x720 render |
| Acceptance | Pending human approval | Marketplace-scale screenshot inspection and final C43 approval |

Quality gates are 100% statements, lines, and functions; 95.05% branches;
90.37% mutation against a 90% floor; three clean race repetitions; zero known
npm vulnerabilities; and clean ShellCheck. Historical rig evidence is recorded
but explicitly excluded from current shipment evidence.
