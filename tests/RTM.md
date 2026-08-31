# Requirements traceability matrix

| Requirement | Implementation | Automated evidence | Remaining evidence |
| --- | --- | --- | --- |
| Count down to the next F1 session | schedule model and bar pill | all session kinds, durations, sorting, countdown and boundary tests | Buzz bar render |
| Show leader, gaps, flags, and safety-car state live | OpenF1 fold and leaderboard model | event merge, gap, live session, flag, VSC, SC, red and yellow tests | Buzz live/fixture panel render |
| Show weekend in local time | panel schedule | schedule fixtures, sparse metadata and exact ordering tests | Marketplace-scale visual review |
| Show both championships | standings model and panel tables | driver, constructor, fallback and sanitization tests | Buzz panel render |
| Bound public API reads | QML curl and polling cadence | C31, C38, C42 and copy contract | Buzz process/log evidence |
| Avoid accounts, tokens, telemetry, writes, and user data | read-only keyless network paths | manifest contract and security gates | Maintainer review |
| Use the full marketplace description allowance | manifest | exact 500/500 equality and claim test | Live listing refresh |
| Present distinct Formula 1 identity | banner, livery hues, structured panel | banner test, all livery tests, C40 pass | Current 1280x720 approved preview |
| Reject stale proof | rig scripts and C43 | provenance contract and intentional C43 block | Candidate-bound rig and render proofs |
