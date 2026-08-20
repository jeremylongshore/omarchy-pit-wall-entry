import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Pit Wall panel: owns the schedule/standings fetch cycle, the live openf1
// polling loop, and the popup UI. Hosted invisibly by BarWidget.qml, which
// renders `label` in the bar slot.
//
// Pit Wall is deliberately zero-config: there is no settings form. The
// cadences and row counts below are fixed constants — the widget IS the
// configuration.
Panel {
  id: root
  moduleName: "io.github.jeremylongshore.pit-wall"
  ipcTarget: "io.github.jeremylongshore.pit-wall"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar identifies this plugin by the widget mounted in its slot, not by
  // this nested panel (popout coordinator + switchPanelFrom both compare
  // against slot.activeItem).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Fixed behavior. No settings form — these are the omakase defaults.
  readonly property int refreshSec: 900        // schedule + standings cadence
  readonly property int liveRefreshSec: 20     // openf1 poll cadence while live
  readonly property int liveRowsCount: 10      // leaderboard rows shown
  readonly property int standingsRows: 5       // rows per championship table

  function open() {
    openedFromHotkey = false
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // ---- Data state. Raw responses parse into these; last-good values stay
  //      visible when a fetch fails.
  property var schedule: ({ season: "", races: [] })
  property bool scheduleLoaded: false
  property var driverRows: []
  property var constructorRows: []

  // Live-session state, accumulated across tail polls.
  property var liveDrivers: ({})
  property var livePositions: ({})
  property var liveGaps: ({})
  property string liveFetchedFullAt: ""
  property string trackStatus: "green"
  // openf1's authoritative session end (ms). Extends the live window past
  // jolpica's fixed-duration estimate so a red-flagged / restarted session
  // keeps its leaderboard and flag status instead of vanishing at start+180m.
  property double liveSessionEndMs: 0

  // Debug-only clock shift (ms), read from the environment — NOT a user
  // setting, so it never appears in shell.json, the settings form, or the
  // manifest. A test rig exports PIT_WALL_FAKE_OFFSET_MS to rehearse live
  // mode outside a real session window; it is 0 for every real user.
  readonly property double debugTimeOffsetMs: Number(Quickshell.env("PIT_WALL_FAKE_OFFSET_MS")) || 0

  // Re-evaluated every 30s so the countdown ticks without any fetch.
  property double nowMs: Date.now() + debugTimeOffsetMs

  readonly property var raceState: Model.currentOrNext(schedule.races, nowMs)
  // Live if jolpica's estimate says so OR openf1's authoritative window is
  // still open (long race). Either source keeps the leaderboard alive.
  readonly property bool scheduleLive: raceState.status === "live"
  readonly property bool openf1Live: liveSessionEndMs > 0 && nowMs < liveSessionEndMs
  readonly property bool isLive: scheduleLive || openf1Live
  readonly property var liveRowsModel: isLive
    ? Model.boardRows(livePositions, liveGaps, liveDrivers, liveRowsCount) : []
  readonly property string trackTag: isLive ? Model.statusTag(trackStatus) : ""

  // Bar pill. Never silently vanishes: the checkered flag glyph is always
  // present so an unreachable API reads as "loading", not "widget gone".
  //   loading (no schedule yet) : "󰈻 …"
  //   between sessions          : "󰈻 QUALI 2h 14m"
  //   live                      : "󰈻 RACE ▸ VER"  /  "󰈻 RACE ▸ SC"
  //   season over               : ""  (legitimately quiet; slot collapses)
  readonly property string label: {
    if (!scheduleLoaded) return " …"
    if (raceState.status === "off") return ""
    return " " + Model.pillText(raceState, Model.leaderAcronym(liveRowsModel), trackTag)
  }

  readonly property string tooltip: {
    if (!scheduleLoaded) return "Pit Wall — loading F1 schedule…"
    if (raceState.status === "off") return "Pit Wall — season complete"
    var r = raceState.race
    return r.name + " — " + raceState.session.label
      + (isLive ? " · LIVE" : " · " + Qt.formatDateTime(new Date(raceState.session.startMs), "ddd d MMM · HH:mm"))
  }

  function refresh() {
    if (!scheduleProc.running) scheduleProc.running = true
    if (!driversStandingsProc.running) driversStandingsProc.running = true
    if (!constructorStandingsProc.running) constructorStandingsProc.running = true
  }

  // ---- Live polling. While a session window is open, poll openf1 on the
  //      fast timer. Every fetch is byte-bounded (--max-filesize) so an
  //      oversized body can never freeze the shell's UI thread on JSON.parse.
  function liveTick() {
    nowMs = Date.now() + debugTimeOffsetMs
    if (!isLive) return
    if (!liveDriversProc.running) liveDriversProc.running = true
    if (!liveSessionProc.running) liveSessionProc.running = true
    // First tick seeds current order from a bounded 60-minute window (not the
    // whole session history); later ticks take a 3-minute tail. mergeEvents
    // accumulates across ticks, so the order stays complete.
    var since
    if (liveFetchedFullAt === "") {
      liveFetchedFullAt = new Date(nowMs).toISOString()
      since = "&date>=" + new Date(nowMs - 3600000).toISOString()
    } else {
      since = "&date>=" + new Date(nowMs - 180000).toISOString()
    }
    if (!livePositionProc.running) {
      livePositionProc.command = curl("https://api.openf1.org/v1/position?session_key=latest" + since)
      livePositionProc.running = true
    }
    if (!liveGapsProc.running) {
      liveGapsProc.command = curl("https://api.openf1.org/v1/intervals?session_key=latest" + since)
      liveGapsProc.running = true
    }
    // Race control is tiny (~100 rows per session), so it always takes the
    // full history — an SC/red period that began before polling must show.
    if (!raceControlProc.running) {
      raceControlProc.command = curl("https://api.openf1.org/v1/race_control?session_key=latest")
      raceControlProc.running = true
    }
  }

  // Shared curl argv. --max-filesize caps the body (openf1 position feeds can
  // be large); curl exits non-zero past the cap, the collector gets nothing,
  // and the parser keeps last-good — never a UI-thread stall.
  function curl(url) {
    return ["curl", "-fsS", "--max-time", "15", "--max-filesize", "8000000", url]
  }

  onIsLiveChanged: {
    // The live-refresh Timer's triggeredOnStart already fires liveTick() the
    // moment it starts, so entering live needs no explicit call here.
    if (!isLive) {
      // Session over: drop accumulated state so the next session starts clean.
      livePositions = ({})
      liveGaps = ({})
      liveDrivers = ({})
      liveFetchedFullAt = ""
      trackStatus = "green"
      liveSessionEndMs = 0
    }
  }

  Process {
    id: scheduleProc
    command: root.curl("https://api.jolpi.ca/ergast/f1/current.json?limit=30")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseSchedule(text)
        if (parsed.races.length) {
          root.schedule = parsed
          root.scheduleLoaded = true
        }
      }
    }
  }

  Process {
    id: driversStandingsProc
    command: root.curl("https://api.jolpi.ca/ergast/f1/current/driverstandings.json")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rows = Model.parseStandings(text, "DriverStandings")
        if (rows.length) root.driverRows = rows
      }
    }
  }

  Process {
    id: constructorStandingsProc
    command: root.curl("https://api.jolpi.ca/ergast/f1/current/constructorstandings.json")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rows = Model.parseStandings(text, "ConstructorStandings")
        if (rows.length) root.constructorRows = rows
      }
    }
  }

  Process {
    id: liveDriversProc
    command: root.curl("https://api.openf1.org/v1/drivers?session_key=latest")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var map = Model.parseDrivers(text)
        var any = false
        for (var k in map) { any = true; break }
        if (any) root.liveDrivers = map
      }
    }
  }

  // openf1's session record is the authority on when the session actually
  // ends; pickLiveSession returns the row active at nowMs (else null).
  Process {
    id: liveSessionProc
    command: root.curl("https://api.openf1.org/v1/sessions?session_key=latest")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var s = Model.pickLiveSession(text, root.nowMs)
        root.liveSessionEndMs = s ? Date.parse(s.date_end) : 0
      }
    }
  }

  Process {
    id: livePositionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.livePositions = Model.mergeEvents(root.livePositions, text)
    }
  }

  Process {
    id: liveGapsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.liveGaps = Model.mergeEvents(root.liveGaps, text)
    }
  }

  Process {
    id: raceControlProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.trackStatus = Model.foldTrackStatus(root.trackStatus, text)
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.liveRefreshSec * 1000
    running: root.isLive
    repeat: true
    triggeredOnStart: true
    onTriggered: root.liveTick()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now() + root.debugTimeOffsetMs
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Fan the refresh out to every monitor's widget. One bar exists per
    // screen; broadcast() lives on the BarWidget host, so route through it —
    // a panel-local refresh() would leave the other monitors stale.
    function refresh(): void {
      if (root.hostWidget && typeof root.hostWidget.broadcast === "function")
        root.hostWidget.broadcast("refresh")
      else root.refresh()
    }
  }

  // ---- Popup UI.
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(12)

          // ---- Hero: race name, round/circuit, countdown or live badge.
          Item {
            width: parent.width
            height: heroCol.implicitHeight

            Column {
              id: heroCol
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              spacing: Style.space(4)

              Text {
                text: !root.scheduleLoaded ? "LOADING…"
                  : (root.raceState.status === "off" ? "SEASON COMPLETE" : root.raceState.race.name.toUpperCase())
                textFormat: Text.PlainText
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: 1
              }

              Text {
                visible: !root.scheduleLoaded || root.raceState.status !== "off"
                text: !root.scheduleLoaded ? "Fetching schedule from jolpica…"
                  : "ROUND " + root.raceState.race.round + " · " + root.raceState.race.circuit.toUpperCase()
                textFormat: Text.PlainText
                color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Row {
                visible: root.scheduleLoaded && root.raceState.status !== "off"
                spacing: Style.space(8)

                Rectangle {
                  visible: root.isLive
                  width: liveText.implicitWidth + Style.space(12)
                  height: liveText.implicitHeight + Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Style.cornerRadius
                  color: root.bar ? root.bar.urgent : Color.urgent

                  Text {
                    id: liveText
                    anchors.centerIn: parent
                    text: root.trackTag === "" ? "● LIVE" : "● LIVE · " + root.trackTag
                    textFormat: Text.PlainText
                    color: root.bar ? root.bar.background : Color.background
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Text {
                  text: root.raceState.status === "off" ? "" : (root.isLive
                    ? root.raceState.session.label
                    : root.raceState.session.label + " in " + Model.countdown(root.raceState.msUntil))
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.display
                  // Live is the urgent state, so it carries the bold weight
                  // (paired with the red LIVE badge); the idle countdown is
                  // regular weight.
                  font.bold: root.isLive
                }
              }
            }
          }

          // ---- Live leaderboard.
          Column {
            visible: root.isLive && root.liveRowsModel.length > 0
            width: parent.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

            PanelSectionHeader {
              text: "LIVE TIMING"
              leftPadding: Style.space(16)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Repeater {
              model: root.liveRowsModel

              Item {
                required property var modelData
                width: contentColumn.width
                height: Style.space(22)

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(26)
                  text: "P" + modelData.pos
                  textFormat: Text.PlainText
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(50)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.acronym
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: modelData.pos === 1
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(110)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.team
                  textFormat: Text.PlainText
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: Style.space(140)
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.gap
                  textFormat: Text.PlainText
                  color: root.bar ? Qt.darker(root.bar.foreground, modelData.pos === 1 ? 1.0 : 1.3) : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          // ---- Weekend schedule.
          Column {
            visible: root.scheduleLoaded && root.raceState.status !== "off"
            width: parent.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

            PanelSectionHeader {
              text: "WEEKEND · LOCAL TIME"
              leftPadding: Style.space(16)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Repeater {
              model: root.raceState.status === "off" ? [] : root.raceState.race.sessions

              Item {
                required property var modelData
                readonly property bool isPast: modelData.endMs <= root.nowMs
                readonly property bool isNow: root.nowMs >= modelData.startMs && root.nowMs < modelData.endMs
                width: contentColumn.width
                height: Style.space(22)

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  textFormat: Text.PlainText
                  color: {
                    var fg = root.bar ? root.bar.foreground : Color.foreground
                    if (isNow) return root.bar ? root.bar.urgent : Color.urgent
                    return isPast ? Qt.darker(fg, 1.6) : fg
                  }
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: isNow
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  text: isNow ? "IN PROGRESS" : Qt.formatDateTime(new Date(modelData.startMs), "ddd HH:mm")
                  textFormat: Text.PlainText
                  color: {
                    var fg = root.bar ? root.bar.foreground : Color.foreground
                    if (isNow) return root.bar ? root.bar.urgent : Color.urgent
                    return isPast ? Qt.darker(fg, 1.6) : Qt.darker(fg, 1.3)
                  }
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }

          // ---- Championship standings, drivers and constructors side by side.
          Column {
            visible: root.driverRows.length > 0
            width: parent.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

            PanelSectionHeader {
              text: "CHAMPIONSHIP"
              leftPadding: Style.space(16)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Item {
              width: parent.width
              height: Math.max(driversCol.implicitHeight, constructorsCol.implicitHeight)

              // ---- Drivers (left half).
              Column {
                id: driversCol
                anchors.left: parent.left
                width: (parent.width - Style.space(1)) / 2
                spacing: Style.space(2)

                Repeater {
                  model: root.driverRows.slice(0, root.standingsRows)

                  Item {
                    required property var modelData
                    width: driversCol.width
                    height: Style.space(20)

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.pos + "  " + (modelData.code || modelData.name)
                      textFormat: Text.PlainText
                      color: root.bar ? root.bar.foreground : Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(20)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.points
                      textFormat: Text.PlainText
                      color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }

              // Hairline splitting the two independently-numbered lists, so a
              // driver's points and the next constructor's rank never fuse at
              // the midline.
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.spacing.hairline
                color: root.bar ? root.bar.foreground : Color.foreground
                opacity: 0.12
              }

              // ---- Constructors (right half).
              Column {
                id: constructorsCol
                anchors.right: parent.right
                width: (parent.width - Style.space(1)) / 2
                spacing: Style.space(2)

                Repeater {
                  model: root.constructorRows.slice(0, root.standingsRows)

                  Item {
                    required property var modelData
                    width: constructorsCol.width
                    height: Style.space(20)

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.pos + "  " + modelData.name
                      textFormat: Text.PlainText
                      color: root.bar ? root.bar.foreground : Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      width: parent.width - Style.space(56)
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.points
                      textFormat: Text.PlainText
                      color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }
          }

          // Bottom breathing room inside the flickable.
          Item { width: 1; height: Style.space(4) }
        }
      }
    }
  }
}
