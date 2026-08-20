<p align="center"><img src="assets/banner.svg" alt="Pit Wall" width="100%"></p>

# Pit Wall

The next F1 session, counted down in your Omarchy bar. Live timing from the moment it starts.

A bar pill counts down to the next Formula 1 session, `QUALI 2h 14m`, then flips to live timing
the moment the lights go out. `RACE ▸ VER`, lit in your theme's active color. Click it for the
panel: the full weekend schedule in **your local time**, the live leaderboard with gaps to the
leader, and both championship standings.

![Pit Wall preview](preview.png)

## Install

```bash
omarchy plugin add https://github.com/jeremylongshore/omarchy-pit-wall-entry --enable
```

Then add **Pit Wall** to your bar layout (Omarchy menu → Bar, or `~/.config/omarchy/shell.json`).

## What it shows

- **Between sessions.** Pill: next session plus a compact countdown (`FP1 2d 4h`). Panel: race
  name, round, circuit, every session of the weekend in local time (past sessions dimmed, the
  next one bold), plus the top of the drivers' and constructors' championships.
- **During a session.** Pill: session plus leader (`SPRINT ▸ NOR`) in the bar's active color, or
  the flag when it matters (`RACE ▸ SC`). Panel: live leaderboard with position, driver, team,
  and gap to the leader, refreshed every 20 seconds, above the schedule and standings.
- **Middle-click** the pill to force a refresh. `Esc` closes the panel, `Tab` walks to the
  neighboring panel, exactly like the built-in widgets.

## Data sources: free, keyless, no accounts

- [jolpica-f1](https://github.com/jolpica/jolpica-f1) (`api.jolpi.ca`) for the season schedule and
  championship standings. It is the community successor to the Ergast API.
- [OpenF1](https://openf1.org) (`api.openf1.org`) for live session positions, intervals, and race
  control.

Schedule and standings refresh every 15 minutes. Live polling only runs during a session window
and fetches incremental tails (the last few minutes of events), so the widget stays light even
across a full race distance.

## Zero configuration

There is no settings form. Pit Wall picks sensible defaults (15-minute schedule refresh, 20-second
live polling, 10 leaderboard rows, 5 standings rows) and shows the pill all season. The widget is
the configuration.

## Theming

No hardcoded colors. Everything reads the bar's palette (`foreground`, `urgent`, the panel
surfaces) and the shell's typography scale, so Pit Wall looks native in every Omarchy theme.

## Remove

```bash
omarchy plugin remove io.github.jeremylongshore.pit-wall
```

## Development

The data layer (`Model.js`) is pure functions shared between the QML runtime and node:

```bash
node --test tests/*.test.js
```

Fixtures under `tests/fixtures/` are real captured responses from both APIs.

## License

MIT. See [LICENSE](LICENSE).
