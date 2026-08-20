import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Pit Wall panel: owns the schedule/standings fetch cycle, the live openf1
// polling loop, and the popup UI. Hosted invisibly by BarWidget.qml, which
// renders `label` in the bar slot.
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
  property var driverRows: []
  property var constructorRows: []

  // Live-session state, accumulated across tail polls.
  property var liveDrivers: ({})
  property var livePositions: ({})
  property var liveGaps: ({})
  property string liveSessionKey: ""
  property string liveFetchedFullAt: ""

  // Debug-only clock shift (ms) so a test rig can rehearse live mode outside
  // a real session window. Stays 0 in normal use; not surfaced in settings.
  readonly property double debugTimeOffsetMs: Number(setting("debugTimeOffsetMs", 0)) || 0

  // Re-evaluated every 30s so the countdown ticks without any fetch.
  property double nowMs: Date.now() + debugTimeOffsetMs

  readonly property var raceState: Model.currentOrNext(schedule.races, nowMs)
  readonly property bool isLive: raceState.status === "live"
  readonly property var liveRowsModel: isLive
    ? Model.boardRows(livePositions, liveGaps, liveDrivers, liveRowsCount) : []

  readonly property int refreshSec: Math.max(300, parseInt(setting("refreshIntervalSec", 900), 10) || 900)
  readonly property int liveRefreshSec: Math.max(10, parseInt(setting("liveRefreshSec", 20), 10) || 20)
  readonly property int liveRowsCount: Math.max(3, parseInt(setting("liveRows", 10), 10) || 10)
  readonly property int standingsRows: Math.max(3, parseInt(setting("standingsRows", 5), 10) || 5)
  readonly property bool hideBetweenWeekends: String(setting("hideBetweenWeekends", "Off")) === "On"

  // Bar pill. Collapses (empty label) with no data, or between weekends when
  // the user asked for a quiet bar.
  readonly property string label: {
    if (raceState.status === "off") return ""
    if (hideBetweenWeekends && raceState.status === "next" && raceState.msUntil > 24 * 3600000) return ""
    // nf-fa-flag_checkered leads the pill so the slot reads as F1 at a glance.
    return " " + Model.pillText(raceState, Model.leaderAcronym(liveRowsModel))
  }

  readonly property string tooltip: {
    if (raceState.status === "off") return ""
    var r = raceState.race
    return r.name + " — " + raceState.session.label
      + (isLive ? " · LIVE" : " · " + Qt.formatDateTime(new Date(raceState.session.startMs), "ddd d MMM · HH:mm"))
  }

  function refresh() {
    if (!scheduleProc.running) scheduleProc.running = true
    if (!driversStandingsProc.running) driversStandingsProc.running = true
    if (!constructorStandingsProc.running) constructorStandingsProc.running = true
  }

  // ---- Live polling. While jolpica says a session window is open, poll
  //      openf1 on the fast timer: full position history once per session,
  //      then only the last three minutes of events, merged into state.
  function liveTick() {
    nowMs = Date.now() + debugTimeOffsetMs
    if (!isLive) return
    if (!liveDriversProc.running) liveDriversProc.running = true
    var since = ""
    if (liveFetchedFullAt === "") {
      liveFetchedFullAt = new Date(nowMs).toISOString()
    } else {
      since = "&date>=" + new Date(nowMs - 180000).toISOString()
    }
    if (!livePositionProc.running) {
      livePositionProc.command = ["curl", "-fsS", "--max-time", "15",
        "https://api.openf1.org/v1/position?session_key=latest" + since]
      livePositionProc.running = true
    }
    if (!liveGapsProc.running) {
      liveGapsProc.command = ["curl", "-fsS", "--max-time", "15",
        "https://api.openf1.org/v1/intervals?session_key=latest" + (since === "" ? "&date>=" + new Date(nowMs - 600000).toISOString() : since)]
      liveGapsProc.running = true
    }
  }

  onIsLiveChanged: {
    if (isLive) {
      liveTick()
    } else {
      // Session over: drop accumulated state so the next session starts clean.
      livePositions = ({})
      liveGaps = ({})
      liveDrivers = ({})
      liveFetchedFullAt = ""
    }
  }

  Process {
    id: scheduleProc
    command: ["curl", "-fsS", "--max-time", "15", "https://api.jolpi.ca/ergast/f1/current.json?limit=30"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseSchedule(text)
        if (parsed.races.length) root.schedule = parsed
      }
    }
  }

  Process {
    id: driversStandingsProc
    command: ["curl", "-fsS", "--max-time", "15", "https://api.jolpi.ca/ergast/f1/current/driverstandings.json"]
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
    command: ["curl", "-fsS", "--max-time", "15", "https://api.jolpi.ca/ergast/f1/current/constructorstandings.json"]
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
    command: ["curl", "-fsS", "--max-time", "15", "https://api.openf1.org/v1/drivers?session_key=latest"]
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
    function refresh(): void { root.refresh() }
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
                text: root.raceState.status === "off" ? "SEASON COMPLETE" : root.raceState.race.name.toUpperCase()
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: 1
              }

              Text {
                visible: root.raceState.status !== "off"
                text: root.raceState.status === "off" ? "" :
                  "ROUND " + root.raceState.race.round + " · " + root.raceState.race.circuit.toUpperCase()
                color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Row {
                visible: root.raceState.status !== "off"
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
                    text: "● LIVE"
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
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.display
                  font.bold: !root.isLive
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
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(50)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.acronym
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
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.5) : Color.muted
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
                  color: root.bar ? Qt.darker(root.bar.foreground, modelData.pos === 1 ? 1.0 : 1.3) : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          // ---- Weekend schedule.
          Column {
            visible: root.raceState.status !== "off"
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
                  color: {
                    var fg = root.bar ? root.bar.foreground : Color.foreground
                    if (isNow) return root.bar ? root.bar.urgent : Color.urgent
                    return isPast ? Qt.darker(fg, 1.7) : fg
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
                  color: {
                    var fg = root.bar ? root.bar.foreground : Color.foreground
                    if (isNow) return root.bar ? root.bar.urgent : Color.urgent
                    return isPast ? Qt.darker(fg, 1.7) : Qt.darker(fg, 1.3)
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

            Row {
              width: parent.width

              Column {
                width: parent.width / 2
                spacing: Style.space(2)

                Repeater {
                  model: root.driverRows.slice(0, root.standingsRows)

                  Item {
                    required property var modelData
                    width: contentColumn.width / 2
                    height: Style.space(20)

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.pos + "  " + (modelData.code || modelData.name)
                      color: root.bar ? root.bar.foreground : Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.points
                      color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }

              Column {
                width: parent.width / 2
                spacing: Style.space(2)

                Repeater {
                  model: root.constructorRows.slice(0, root.standingsRows)

                  Item {
                    required property var modelData
                    width: contentColumn.width / 2
                    height: Style.space(20)

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.pos + "  " + modelData.name
                      color: root.bar ? root.bar.foreground : Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      width: parent.parent.width - Style.space(60)
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.points
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
