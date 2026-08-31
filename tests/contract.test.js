const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const root = path.join(__dirname, "..")
const read = name => fs.readFileSync(path.join(root, name), "utf8")

test("marketplace copy uses all 500 characters for the shipped F1 story", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(manifest.description.length, 500)
  assert.equal(manifest.barWidget.description.length, 500)
  assert.equal(manifest.description, manifest.barWidget.description)
  for (const claim of [
    "race-weekend command post", "counts down", "leader, gaps, flags",
    "local time", "driver and constructor standings", "every 15 minutes",
    "every 20 seconds", "No account, token, telemetry, writes, or user data"
  ]) assert.match(manifest.description, new RegExp(claim))
})

test("banner names and illustrates Pit Wall rather than a generic widget", () => {
  const banner = read("assets/banner.svg")
  assert.match(banner, /PIT WALL/)
  assert.match(banner, /RACE &#9656; VER/)
  assert.match(banner, /<(?:path|circle|line|polyline|linearGradient)\b/)
})

test("render tooling requires exact 1280x720 provenance and approval", () => {
  const render = read("scripts/rig-render.sh")
  assert.match(render, /OMARCHY_RIG_RESOLUTION:-1280x720/)
  assert.match(render, /e2e\/bin/)
  assert.match(render, /export PATH=.*e2e\/bin/)
  assert.match(render, /rawShellLogSha256/)
  assert.match(render, /visualInspection:\{status:"pending"/)
  assert.match(read("scripts/approve-preview.sh"), /product value is visible without reading the README/)
})

test("render fixture proves a complete live safety-car race without network access", () => {
  const fixtureCurl = path.join(root, "e2e/bin/curl")
  assert.ok(fs.statSync(fixtureCurl).mode & 0o111, "fixture curl must be executable")
  const env = { ...process.env, XDG_RUNTIME_DIR: process.env.TMPDIR || "/tmp" }
  const run = url => execFileSync(fixtureCurl, ["-fsS", "--", url], { env, encoding: "utf8" })

  const schedule = JSON.parse(run("https://api.jolpi.ca/ergast/f1/current.json?limit=30"))
  const drivers = JSON.parse(run("https://api.openf1.org/v1/drivers?session_key=latest"))
  const positions = JSON.parse(run("https://api.openf1.org/v1/position?session_key=latest"))
  const control = JSON.parse(run("https://api.openf1.org/v1/race_control?session_key=latest"))

  assert.equal(schedule.MRData.RaceTable.Races[0].raceName, "Belgian Grand Prix")
  assert.equal(schedule.MRData.RaceTable.Races.length, 3)
  assert.equal(drivers.length, 6)
  assert.equal(positions[0].position, 1)
  assert.match(control.at(-1).message, /SAFETY CAR DEPLOYED/)
  assert.match(read("e2e/rig-before-capture.sh"), /schedule driver-standings constructor-standings drivers session position intervals race-control/)
  assert.throws(() => run("https://example.com/not-an-f1-api"), /Command failed/)
})

test("tracked source contains no unresolved merge-conflict markers", () => {
  const files = execFileSync("git", ["ls-files", "-z"], { cwd: root })
    .toString().split("\0").filter(Boolean)
  for (const file of files) {
    const absolute = path.join(root, file)
    if (!fs.existsSync(absolute)) continue
    const body = fs.readFileSync(absolute)
    if (body.includes(0)) continue
    assert.doesNotMatch(body.toString("utf8"), /^(?:<{7}|={7}|>{7})(?: |$)/m, file)
  }
})

test("CI pins actions and runs every local quality gate", () => {
  const workflow = read(".github/workflows/test.yml")
  assert.doesNotMatch(workflow, /uses:\s+[^\s]+@v\d+/)
  for (const command of [
    "npm ci", "npm run audit:deps", "npm test", "npm run test:race",
    "npm run test:mutation", "npm run audit", "shellcheck"
  ]) assert.match(workflow, new RegExp(command.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.match(workflow, /e2e\/bin\/\*/)
})
