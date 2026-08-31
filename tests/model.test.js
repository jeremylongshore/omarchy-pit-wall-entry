const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const Model = require("../Model.js")

const fixture = (name) =>
  fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")

const scheduleRaw = fixture("jolpica-schedule.json")
const driversStandingsRaw = fixture("jolpica-driver-standings.json")
const constructorsRaw = fixture("jolpica-constructor-standings.json")
const openf1SessionsRaw = fixture("openf1-sessions.json")
const openf1DriversRaw = fixture("openf1-drivers.json")
const positionsRaw = fixture("openf1-position-tail.json")
const intervalsRaw = fixture("openf1-intervals-tail.json")

test("parseSchedule reads the season and orders races by round", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  assert.equal(schedule.season, "2026")
  assert.ok(schedule.races.length >= 12)
  const rounds = schedule.races.map((r) => r.round)
  assert.deepEqual(rounds, [...rounds].sort((a, b) => a - b))
})

test("parseSchedule captures the Dutch GP sprint weekend sessions in order", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const dutch = schedule.races.find((r) => r.name === "Dutch Grand Prix")
  assert.ok(dutch)
  assert.equal(dutch.locality, "Zandvoort")
  assert.deepEqual(
    dutch.sessions.map((s) => s.kind),
    ["fp1", "sprintQualifying", "sprint", "qualifying", "race"]
  )
  const race = dutch.sessions[dutch.sessions.length - 1]
  assert.equal(race.startMs, Date.parse("2026-08-23T13:00:00Z"))
  const starts = dutch.sessions.map((s) => s.startMs)
  assert.deepEqual(starts, [...starts].sort((a, b) => a - b))
})

test("parseSchedule tolerates garbage and empty input", () => {
  assert.deepEqual(Model.parseSchedule("not json"), { season: "", races: [] })
  assert.deepEqual(Model.parseSchedule(""), { season: "", races: [] })
  assert.deepEqual(Model.parseSchedule('{"MRData":{}}'), { season: "", races: [] })
})

test("currentOrNext finds the upcoming session between weekends", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  // Wednesday before the Dutch GP, 12:00 UTC.
  const now = Date.parse("2026-08-19T12:00:00Z")
  const state = Model.currentOrNext(schedule.races, now)
  assert.equal(state.status, "next")
  assert.equal(state.race.name, "Dutch Grand Prix")
  assert.equal(state.session.kind, "fp1")
  assert.equal(state.msUntil, Date.parse("2026-08-21T10:30:00Z") - now)
})

test("currentOrNext reports live during a session window", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const state = Model.currentOrNext(schedule.races, Date.parse("2026-08-23T13:45:00Z"))
  assert.equal(state.status, "live")
  assert.equal(state.session.kind, "race")
  assert.equal(state.race.name, "Dutch Grand Prix")
})

test("currentOrNext reports off after the season ends", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const state = Model.currentOrNext(schedule.races, Date.parse("2027-06-01T00:00:00Z"))
  assert.equal(state.status, "off")
})

test("countdown keeps the two most significant units, zero-padded for stable width", () => {
  assert.equal(Model.countdown(2 * 86400000 + 4 * 3600000), "2d 4h")
  assert.equal(Model.countdown(2 * 3600000 + 14 * 60000), "2h 14m")
  assert.equal(Model.countdown(1 * 3600000 + 5 * 60000), "1h 05m")
  assert.equal(Model.countdown(14 * 60000), "14m")
  // Sub-ten-minutes is zero-padded so the pill doesn't lose a character
  // exactly when the countdown is most worth watching.
  assert.equal(Model.countdown(9 * 60000), "09m")
  assert.equal(Model.countdown(60000), "01m")
  assert.equal(Model.countdown(10000), "now")
})

test("clean strips angle brackets and control chars, caps length, defusing rich-text sinks", () => {
  assert.equal(Model.clean("<img src=x onerror=1 width=90000>"), "img src=x onerror=1 width=90000")
  assert.equal(Model.clean("Red Bull Racing"), "Red Bull Racing")   // spaces + normal text survive
  assert.equal(Model.clean("VER\x01"), "VER")               // control chars gone
  assert.equal(Model.clean(null), "")
  assert.equal(Model.clean(undefined), "")
  assert.equal(Model.clean("x".repeat(200), 32).length, 32)
})

test("parsers sanitize API strings so no tag reaches a Text element", () => {
  const drivers = Model.parseDrivers(JSON.stringify([
    { driver_number: 1, name_acronym: "<img src=http://evil>", team_name: "Team <b>X</b>" }
  ]))
  assert.equal(drivers["1"].acronym.indexOf("<"), -1)
  assert.equal(drivers["1"].team.indexOf(">"), -1)

  const standings = Model.parseStandings(JSON.stringify({
    MRData: { StandingsTable: { StandingsLists: [{ DriverStandings: [
      { position: "1", points: "<x>", Driver: { familyName: "<img>", code: "<a>" }, Constructors: [{ name: "<b>" }] }
    ] }] } }
  }), "DriverStandings")
  assert.equal(standings[0].name.indexOf("<"), -1)
  assert.equal(standings[0].points.indexOf("<"), -1)

  const sched = Model.parseSchedule(JSON.stringify({
    MRData: { RaceTable: { season: "2026", Races: [
      { round: "1", raceName: "<img src=x>GP", date: "2026-03-01", time: "13:00:00Z",
        Circuit: { circuitName: "<b>Track</b>" } }
    ] } }
  }))
  assert.equal(sched.races[0].name.indexOf("<"), -1)
  assert.equal(sched.races[0].circuit.indexOf(">"), -1)
})

test("pillText renders countdown and live variants", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const next = Model.currentOrNext(schedule.races, Date.parse("2026-08-21T08:30:00Z"))
  assert.equal(Model.pillText(next), "FP1 2h 00m")
  const live = Model.currentOrNext(schedule.races, Date.parse("2026-08-23T13:45:00Z"))
  assert.equal(Model.pillText(live, "NOR"), "RACE ▸ NOR")
  assert.equal(Model.pillText(live, ""), "RACE ▸ LIVE")
  assert.equal(Model.pillText({ status: "off" }), "")
  assert.equal(Model.pillText(null), "")
})

test("parseStandings reads drivers with code, team, points", () => {
  const rows = Model.parseStandings(driversStandingsRaw, "DriverStandings")
  assert.ok(rows.length >= 20)
  assert.equal(rows[0].pos, 1)
  assert.equal(rows[0].code, "ANT")
  assert.equal(rows[0].team, "Mercedes")
  assert.equal(rows[0].points, "219")
})

test("parseStandings reads constructors", () => {
  const rows = Model.parseStandings(constructorsRaw, "ConstructorStandings")
  assert.ok(rows.length >= 10)
  assert.equal(rows[0].name, "Mercedes")
  assert.equal(rows[0].points, "379")
  assert.equal(rows[1].name, "Ferrari")
})

test("parseStandings tolerates garbage", () => {
  assert.deepEqual(Model.parseStandings("nope", "DriverStandings"), [])
  assert.deepEqual(Model.parseStandings("{}", "DriverStandings"), [])
})

test("parseDrivers maps driver numbers to acronyms and teams", () => {
  const map = Model.parseDrivers(openf1DriversRaw)
  assert.equal(map["1"].acronym, "NOR")
  assert.equal(map["1"].team, "McLaren")
  assert.ok(Object.keys(map).length >= 18)
})

test("latestByDriver keeps only the newest row per driver", () => {
  const rows = [
    { driver_number: 5, date: "2026-08-23T14:00:00+00:00", position: 3 },
    { driver_number: 5, date: "2026-08-23T14:05:00+00:00", position: 1 },
    { driver_number: 7, date: "2026-08-23T13:59:00+00:00", position: 2 }
  ]
  const latest = Model.latestByDriver(rows)
  assert.equal(latest["5"].position, 1)
  assert.equal(latest["7"].position, 2)
})

test("leaderboard joins position, driver, and interval feeds in order", () => {
  const rows = Model.leaderboard(positionsRaw, openf1DriversRaw, intervalsRaw, 0)
  assert.ok(rows.length >= 15)
  const positions = rows.map((r) => r.pos)
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b))
  assert.equal(rows[0].gap, "LEADER")
  for (const row of rows) {
    assert.ok(row.acronym.length >= 2)
    assert.equal(typeof row.gap, "string")
  }
})

test("leaderboard respects the row limit and bad input", () => {
  const rows = Model.leaderboard(positionsRaw, openf1DriversRaw, intervalsRaw, 10)
  assert.equal(rows.length, 10)
  assert.deepEqual(Model.leaderboard("garbage", "{}", "[]", 10), [])
  assert.deepEqual(Model.leaderboard("[]", "{}", "[]", 10), [])
})

test("mergeEvents folds tail batches into accumulated state", () => {
  const first = Model.mergeEvents({}, JSON.stringify([
    { driver_number: 5, date: "2026-08-23T14:00:00+00:00", position: 3 },
    { driver_number: 7, date: "2026-08-23T14:00:01+00:00", position: 1 }
  ]))
  const second = Model.mergeEvents(first, JSON.stringify([
    { driver_number: 5, date: "2026-08-23T14:05:00+00:00", position: 1 },
    { driver_number: 7, date: "2026-08-23T13:59:00+00:00", position: 9 }
  ]))
  assert.equal(second["5"].position, 1)   // newer event wins
  assert.equal(second["7"].position, 1)   // stale event ignored
  assert.notEqual(first, second)          // new object, not in-place mutation
  assert.equal(first["5"].position, 3)
  assert.equal(Model.mergeEvents(first, "garbage"), first)
  assert.equal(Model.mergeEvents(first, "[]"), first)
})

test("boardRows reads accumulated maps directly", () => {
  const posMap = Model.mergeEvents({}, positionsRaw)
  const gapsMap = Model.mergeEvents({}, intervalsRaw)
  const drivers = Model.parseDrivers(openf1DriversRaw)
  const rows = Model.boardRows(posMap, gapsMap, drivers, 5)
  assert.equal(rows.length, 5)
  assert.equal(rows[0].gap, "LEADER")
})

test("gapText formats leader, lapped, and numeric gaps", () => {
  assert.equal(Model.gapText(null, true), "LEADER")
  assert.equal(Model.gapText(null, false), "")
  assert.equal(Model.gapText({ gap_to_leader: "+2 LAPS" }, false), "+2 LAPS")
  assert.equal(Model.gapText({ gap_to_leader: 1.2345 }, false), "+1.234")
  assert.equal(Model.gapText({ gap_to_leader: null }, false), "")
})

test("pickLiveSession trusts openf1 windows and skips cancelled rows", () => {
  const during = Date.parse("2026-08-21T10:45:00Z")
  const live = Model.pickLiveSession(openf1SessionsRaw, during)
  assert.ok(live)
  assert.equal(live.session_name, "Practice 1")
  const between = Date.parse("2026-08-21T12:00:00Z")
  assert.equal(Model.pickLiveSession(openf1SessionsRaw, between), null)
  assert.equal(Model.pickLiveSession("junk", during), null)
})

const raceControlRaw = fixture("openf1-race-control.json")

test("foldTrackStatus replays the real Hungary VSC sequence correctly", () => {
  const events = JSON.parse(raceControlRaw)
  // Up to just after VSC deployment (14:22:55Z): status is vsc.
  const untilVsc = events.filter((e) => e.date <= "2026-07-26T14:23:00+00:00")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify(untilVsc)), "vsc")
  // "VSC ENDING" alone does not clear it — only TRACK CLEAR does.
  const untilEnding = events.filter((e) => e.date <= "2026-07-26T14:24:15+00:00")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify(untilEnding)), "vsc")
  const untilClear = events.filter((e) => e.date <= "2026-07-26T14:24:30+00:00")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify(untilClear)), "green")
  // Whole session ends on the chequered flag.
  assert.equal(Model.foldTrackStatus("green", raceControlRaw), "chequered")
})

test("foldTrackStatus handles SC, red, track yellows; ignores sector/driver flags", () => {
  const mk = (over) => Object.assign({ category: "Flag", scope: "Track", flag: null, message: "", date: "2026-01-01T00:00:00" }, over)
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([
    { category: "SafetyCar", message: "SAFETY CAR DEPLOYED", date: "1" }
  ])), "sc")
  assert.equal(Model.foldTrackStatus("sc", JSON.stringify([
    mk({ flag: "GREEN", message: "TRACK CLEAR", date: "2" })
  ])), "green")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([mk({ flag: "RED" })])), "red")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([mk({ flag: "DOUBLE YELLOW" })])), "yellow")
  // Sector-scoped yellow and driver-scoped flags do not touch the pill.
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([
    mk({ flag: "YELLOW", scope: "Sector", sector: 7 }),
    mk({ flag: "BLUE", scope: "Driver", driver_number: 55 })
  ])), "green")
  // Garbage and empty batches keep the current status.
  assert.equal(Model.foldTrackStatus("vsc", "junk"), "vsc")
  assert.equal(Model.foldTrackStatus("vsc", "[]"), "vsc")
  // Out-of-order batch: newest event decides regardless of array order.
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([
    mk({ flag: "GREEN", message: "TRACK CLEAR", date: "9" }),
    { category: "SafetyCar", message: "VSC DEPLOYED", date: "3" }
  ])), "green")
})

test("statusTag maps abnormal statuses only", () => {
  assert.equal(Model.statusTag("sc"), "SC")
  assert.equal(Model.statusTag("vsc"), "VSC")
  assert.equal(Model.statusTag("red"), "RED")
  assert.equal(Model.statusTag("yellow"), "YEL")
  assert.equal(Model.statusTag("green"), "")
  assert.equal(Model.statusTag("chequered"), "")
  assert.equal(Model.statusTag(undefined), "")
})

test("pillText: track status outranks the leader while live", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const live = Model.currentOrNext(schedule.races, Date.parse("2026-08-23T13:45:00Z"))
  assert.equal(Model.pillText(live, "NOR", "SC"), "RACE ▸ SC")
  assert.equal(Model.pillText(live, "NOR", ""), "RACE ▸ NOR")
  assert.equal(Model.pillText(live, "", ""), "RACE ▸ LIVE")
})

test("leaderAcronym reads the front of the field", () => {
  const rows = Model.leaderboard(positionsRaw, openf1DriversRaw, intervalsRaw, 0)
  assert.equal(Model.leaderAcronym(rows), rows[0].acronym)
  assert.equal(Model.leaderAcronym([]), "")
})

// ------------------------------------------------------------ country codes

test("countryFlag returns FIA three-letter codes, never emoji", () => {
  // Emoji flags were the first attempt and they are a trap: a flag is a pair of
  // regional-indicator codepoints that only renders as a flag if the system has
  // an emoji font. Without one every race becomes two empty boxes and the panel
  // looks broken rather than plain. The rig demonstrated exactly that.
  const cases = { Netherlands: "NED", Italy: "ITA", Spain: "ESP", UK: "GBR",
                  "United Kingdom": "GBR", USA: "USA", Monaco: "MON",
                  Azerbaijan: "AZE", UAE: "UAE" }
  for (const [country, code] of Object.entries(cases)) {
    assert.equal(Model.countryFlag(country), code, country)
  }
  for (const v of Object.values(cases)) {
    assert.match(v, /^[A-Z]{3}$/, v)
    assert.ok(v.codePointAt(0) < 128, "must be plain ASCII")
  }
})

test("an unrecognised country renders nothing rather than a placeholder", () => {
  for (const bad of ["Atlantis", "", null, undefined, "   "]) {
    assert.equal(Model.countryFlag(bad), "")
  }
})

test("upcomingRaces returns only rounds after the current one", () => {
  const races = [{ round: 11 }, { round: 12 }, { round: 13 }, { round: 14 }, { round: 15 }]
  assert.deepEqual(Model.upcomingRaces(races, 12, 3).map((r) => r.round), [13, 14, 15])
  assert.deepEqual(Model.upcomingRaces(races, 15, 3), [], "season end must be empty")
  assert.deepEqual(Model.upcomingRaces([], 1, 3), [])
})

test("raceDateText reads the race session, falling back to the first", () => {
  const race = { sessions: [
    { kind: "fp1", startMs: Date.parse("2026-09-04T10:00:00Z") },
    { kind: "race", startMs: Date.parse("2026-09-06T13:00:00Z") }] }
  assert.equal(Model.raceDateText(race, Date.now()), "Sep 6")
  // Some rounds publish practice before the race slot is confirmed.
  assert.equal(Model.raceDateText({ sessions: [
    { kind: "fp1", startMs: Date.parse("2026-09-04T10:00:00Z") }] }, Date.now()), "Sep 4")
  assert.equal(Model.raceDateText({ sessions: [] }, Date.now()), "")
  assert.equal(Model.raceDateText(null, Date.now()), "")
})

test("teamHue gives every current livery family a distinct stable identity", () => {
  const cases = {
    Ferrari: 0.005, Mercedes: 0.46, McLaren: 0.065,
    "Red Bull Racing": 0.66, "Racing Bulls": 0.60, "RB F1 Team": 0.60,
    Williams: 0.56, "Aston Martin": 0.42, Alpine: 0.55, Haas: 0.02,
    Sauber: 0.30, Audi: 0.30, Cadillac: 0.12
  }
  for (const [team, hue] of Object.entries(cases)) assert.equal(Model.teamHue(team), hue, team)
  assert.equal(Model.teamHue(null), 0)
  assert.equal(Model.teamHue("Andretti"), Model.teamHue("Andretti"))
  assert.notEqual(Model.teamHue("Andretti"), Model.teamHue("Porsche"))
})

test("countryCode preserves the plain-ASCII countryFlag compatibility alias", () => {
  assert.equal(Model.countryCode(" Netherlands "), "NED")
  assert.equal(Model.countryCode("Unknown"), "")
})

test("parseStandings skips structurally invalid rows and fills documented fallbacks", () => {
  const raw = JSON.stringify({ MRData: { StandingsTable: { StandingsLists: [{ DriverStandings: [
    {},
    { Driver: { driverId: "fallback-driver" }, Constructors: [], position: "", points: "", wins: "" }
  ] }] } } })
  assert.deepEqual(Model.parseStandings(raw, "DriverStandings"), [{
    pos: 2, points: "0", wins: 0, name: "fallback-driver", code: "", team: ""
  }])
  assert.deepEqual(Model.parseStandings(raw, "MissingStandings"), [])
})

test("parseDrivers ignores missing numbers and supplies bounded identity fallbacks", () => {
  assert.deepEqual(Model.parseDrivers("junk"), {})
  assert.deepEqual(Model.parseDrivers("[]"), {})
  const rows = Model.parseDrivers(JSON.stringify([
    {}, { driver_number: null },
    { driver_number: 44, team_name: null, broadcast_name: "Lewis Hamilton" },
    { driver_number: 7, full_name: "Kimi Antonelli" }
  ]))
  assert.deepEqual(rows["44"], { acronym: "#44", team: "", name: "Lewis Hamilton" })
  assert.deepEqual(rows["7"], { acronym: "#7", team: "", name: "Kimi Antonelli" })
})

test("parseSchedule drops empty weekends and maps sparse circuit metadata safely", () => {
  const raw = JSON.stringify({ MRData: { RaceTable: { season: "2026", Races: [
    { round: "bad", raceName: "No Sessions" },
    { round: "2", raceName: "Sparse GP", FirstPractice: { date: "bad" },
      date: "2026-03-08", Circuit: {} }
  ] } } })
  const schedule = Model.parseSchedule(raw)
  assert.equal(schedule.races.length, 1)
  assert.equal(schedule.races[0].round, 2)
  assert.equal(schedule.races[0].circuit, "")
  assert.equal(schedule.races[0].locality, "")
  assert.equal(schedule.races[0].country, "")
  assert.equal(schedule.races[0].sessions[0].kind, "race")
})

test("boardRows supports missing metadata and an unlimited result", () => {
  const rows = Model.boardRows({
    "8": { position: 2 }, "9": { position: 1 }
  }, {}, null, 0)
  assert.deepEqual(rows, [
    { pos: 1, num: "9", acronym: "#9", team: "", gap: "LEADER" },
    { pos: 2, num: "8", acronym: "#8", team: "", gap: "" }
  ])
  assert.deepEqual(Model.leaderboard(JSON.stringify([{ driver_number: 9, position: 1, date: "1" }]), {}, "[]", 0), [
    { pos: 1, num: "9", acronym: "#9", team: "", gap: "LEADER" }
  ])
})

test("pickLiveSession ignores invalid windows, exact end boundaries, and cancellation", () => {
  const now = Date.parse("2026-01-01T12:00:00Z")
  const rows = JSON.stringify([
    { date_start: "bad", date_end: "bad" },
    { date_start: "2026-01-01T11:00:00Z", date_end: "2026-01-01T13:00:00Z", is_cancelled: true },
    { session_name: "Race", date_start: "2026-01-01T11:00:00Z", date_end: "2026-01-01T13:00:00Z" }
  ])
  assert.equal(Model.pickLiveSession(rows, now).session_name, "Race")
  assert.equal(Model.pickLiveSession(rows, Date.parse("2026-01-01T13:00:00Z")), null)
  assert.equal(Model.pickLiveSession("[]", now), null)
})

test("all session kinds pin label, short code, duration, and chronological sorting", () => {
  const raw = JSON.stringify({ MRData: { RaceTable: { season: "2026", Races: [
    {
      round: "2", raceName: "Complete Weekend", date: "2026-04-05", time: "13:00:00Z",
      FirstPractice: { date: "2026-04-03", time: "12:00:00Z" },
      SecondPractice: { date: "2026-04-03", time: "16:00:00Z" },
      ThirdPractice: { date: "2026-04-04", time: "10:00:00Z" },
      SprintQualifying: { date: "2026-04-03", time: "08:00:00Z" },
      Sprint: { date: "2026-04-04", time: "08:00:00Z" },
      Qualifying: { date: "2026-04-04", time: "14:00:00Z" }
    },
    { round: "1", raceName: "Earlier Round", date: "2026-03-01", time: "13:00:00Z" }
  ] } } })
  const schedule = Model.parseSchedule(raw)
  assert.deepEqual(schedule.races.map(r => r.round), [1, 2])
  const sessions = schedule.races[1].sessions
  assert.deepEqual(sessions.map(s => [s.kind, s.label, s.short, s.endMs - s.startMs]), [
    ["sprintQualifying", "Sprint Qualifying", "SQ", 45 * 60000],
    ["fp1", "Practice 1", "FP1", 60 * 60000],
    ["fp2", "Practice 2", "FP2", 60 * 60000],
    ["sprint", "Sprint", "SPRINT", 60 * 60000],
    ["fp3", "Practice 3", "FP3", 60 * 60000],
    ["qualifying", "Qualifying", "QUALI", 60 * 60000],
    ["race", "Race", "RACE", 180 * 60000]
  ])
})

test("country table pins every supported human spelling and FIA code", () => {
  const countries = {
    australia: "AUS", bahrain: "BRN", "saudi arabia": "SAU", japan: "JPN",
    china: "CHN", usa: "USA", "united states": "USA", america: "USA",
    italy: "ITA", monaco: "MON", canada: "CAN", spain: "ESP", austria: "AUT",
    uk: "GBR", "united kingdom": "GBR", "great britain": "GBR", hungary: "HUN",
    belgium: "BEL", netherlands: "NED", azerbaijan: "AZE", singapore: "SIN",
    mexico: "MEX", brazil: "BRA", qatar: "QAT", uae: "UAE",
    "united arab emirates": "UAE", france: "FRA", portugal: "POR", turkey: "TUR",
    russia: "RUS", germany: "GER", malaysia: "MAS", vietnam: "VIE",
    "south africa": "RSA", korea: "KOR", india: "IND", argentina: "ARG",
    switzerland: "SUI", sweden: "SWE", morocco: "MAR"
  }
  for (const [country, code] of Object.entries(countries)) {
    assert.equal(Model.countryFlag(country), code, country)
    assert.equal(Model.countryCode(country.toUpperCase()), code, `${country} uppercase`)
  }
})

test("currentOrNext honors exact window boundaries and earliest unsorted future", () => {
  const session = (start, end, short) => ({ startMs: start, endMs: end, short })
  const races = [
    { name: "Later", sessions: [session(400, 500, "RACE")] },
    { name: "Sooner", sessions: [session(200, 300, "FP1")] }
  ]
  assert.equal(Model.currentOrNext(races, 100).race.name, "Sooner")
  assert.equal(Model.currentOrNext(races, 200).status, "live")
  assert.equal(Model.currentOrNext(races, 299).status, "live")
  assert.equal(Model.currentOrNext(races, 300).race.name, "Later")
})

test("parseStandings pins constructor fallbacks and exact row order", () => {
  const raw = JSON.stringify({ MRData: { StandingsTable: { StandingsLists: [{ ConstructorStandings: [
    { position: "2", points: "42", wins: "1", Constructor: { name: "Ferrari" } },
    { position: "", points: null, wins: null, Constructor: { constructorId: "future-team" } }
  ] }] } } })
  assert.deepEqual(Model.parseStandings(raw, "ConstructorStandings"), [
    { pos: 2, points: "42", wins: 1, name: "Ferrari", code: "", team: "" },
    { pos: 2, points: "0", wins: 0, name: "future-team", code: "", team: "" }
  ])
})

test("event folding keeps exact-date state and copies a null base safely", () => {
  const older = { driver_number: 1, date: "1", position: 2 }
  const equal = { driver_number: 1, date: "1", position: 9 }
  const latest = Model.latestByDriver([older, equal])
  assert.equal(latest["1"], older)
  const merged = Model.mergeEvents(null, JSON.stringify([older, equal]))
  assert.deepEqual(merged["1"], older)
  assert.deepEqual(Model.mergeEvents(null, "[]"), {})
})

test("gapText prefixes plain string gaps once and preserves already-prefixed gaps", () => {
  assert.equal(Model.gapText({ gap_to_leader: "2.500" }, false), "+2.500")
  assert.equal(Model.gapText({ gap_to_leader: "+2.500" }, false), "+2.500")
  assert.equal(Model.gapText({ gap_to_leader: "" }, false), "")
})

test("upcomingRaces defaults to three and handles null input", () => {
  const races = [{ round: 2 }, { round: 3 }, { round: 4 }, { round: 5 }]
  assert.deepEqual(Model.upcomingRaces(races, 1).map(r => r.round), [2, 3, 4])
  assert.deepEqual(Model.upcomingRaces(null, 1), [])
  assert.deepEqual(Model.upcomingRaces(races, 1, 1).map(r => r.round), [2])
})

test("countdown pins exact threshold and ten-minute padding boundaries", () => {
  assert.equal(Model.countdown(30000), "now")
  assert.equal(Model.countdown(31 * 1000), "01m")
  assert.equal(Model.countdown(10 * 60000), "10m")
  assert.equal(Model.countdown(70 * 60000), "1h 10m")
})

test("raceDateText pins every month abbreviation", () => {
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  for (let month = 0; month < 12; month++) {
    const startMs = Date.UTC(2026, month, 15, 12)
    assert.equal(Model.raceDateText({ sessions: [{ kind: "race", startMs }] }), `${months[month]} 15`)
  }
})

test("unknown team hues pin the stable hash algorithm", () => {
  assert.equal(Model.teamHue("Andretti"), 0.8861111111111111)
  assert.equal(Model.teamHue("Porsche"), 0.26666666666666666)
})
