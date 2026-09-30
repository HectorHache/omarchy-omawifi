import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as M

// Wi-Fi Anchor — the bar entry.
//
// One job: say which access point this radio is holding, and let you hold a
// different one. The mark is drawn (ApGlyph), the number beside it is the
// signal of the access point in use, and the colour is the verdict:
//
//   theme text   anchored on the access point you chose
//   urgent       drifted off it: what you picked is not what you are on
//   dimmed text  no anchor, NetworkManager is choosing
//   faint text   not associated
//
// Left click opens the panel, middle click rescans, right click anchors to the
// best access point right now without opening anything.
BarWidget {
  id: root
  moduleName: "io.github.hectorhache.omawifi"

  // ---- settings (declared in manifest.json, edited in the shell's plugin UI)
  // Values arrive as JSON from shell.json, but a hand-edited file can hold
  // strings ("true"), so every read is tolerant of both.
  function boolSetting(name, fallback) {
    var v = setting(name, fallback)
    if (typeof v === "boolean") return v
    if (typeof v === "string") {
      var s = v.toLowerCase()
      if (s === "true" || s === "1" || s === "yes" || s === "on") return true
      if (s === "false" || s === "0" || s === "no" || s === "off") return false
    }
    return fallback
  }
  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  readonly property bool showSignal: boolSetting("showSignal", true)
  readonly property string ssidOverride: String(setting("ssidOverride", "") || "")
  readonly property bool pinBand: boolSetting("pinBand", false)
  readonly property bool simpleRanking: boolSetting("simpleRanking", false)
  readonly property int refreshSeconds: intSetting("refreshSeconds", 20, 10, 600)
  readonly property int openRefreshSeconds: intSetting("openRefreshSeconds", 5, 2, 60)
  readonly property bool showScores: boolSetting("showScores", true)

  // The setting speaks bands; the script speaks NetworkManager's own vocabulary.
  readonly property string bandPref: {
    var band = String(setting("band", "5 GHz") || "5 GHz")
    if (band === "2.4 GHz") return "bg"
    if (band === "Both") return "auto"
    return "a"
  }

  // The panel's own "2.4 GHz" switch. Session-scoped on purpose: it is a
  // momentary look at the other band, not a preference worth persisting, and a
  // persisted one would silently change the bar's numbers for the next login.
  property bool showAllBands: false

  // ---- live state ----------------------------------------------------------
  property var doc: null            // parsed `omawifi ui` snapshot
  property string errorText: ""     // last hard failure, cleared on a good read
  property string lastMessage: ""   // result of the last action, shown in the panel
  property bool actionFailed: false

  // One command at a time: the panel reads this to block input while the radio
  // is being repinned, because a second mutation would race the first. Only
  // user-visible actions count as busy; a background poll never does, or the
  // panel would blink "working" every few seconds.
  readonly property bool busy: helper.acting

  readonly property string state: doc && doc.ok !== false ? String(doc.state || "offline") : "offline"
  readonly property string tone: M.stateTone(state)
  readonly property bool associated: !!doc && state !== "offline"

  // The colour roles the mark and the number use. barForeground rather than
  // foreground: on a transparent bar the shell has already worked out what
  // reads over the wallpaper, and that answer is barForeground.
  readonly property color baseColor: bar ? bar.barForeground : Color.foreground
  readonly property color alertColor: bar ? bar.urgent : Color.urgent
  readonly property color faceColor:
    tone === "warn" ? alertColor :
    tone === "off" ? Util.alpha(baseColor, 0.45) :
    tone === "calm" ? Util.alpha(baseColor, 0.7) : baseColor

  // Trailing space keeps the number off whatever widget sits to our right in the
  // bar (e.g. a neighbouring plugin), so the reading never looks glued to it.
  readonly property string faceText:
    !showSignal || !associated || !doc || doc.signal === null || doc.signal === undefined
      ? "" : Math.round(doc.signal) + "% "

  readonly property string scriptPath:
    Qt.resolvedUrl("scripts/omawifi").toString().replace("file://", "")

  // Env, not arguments: the script reads the SSID from here, and an SSID can be
  // any text at all, so it never becomes part of a command line.
  readonly property var scriptEnv: {
    var env = {}
    if (ssidOverride !== "") env["OMAWIFI_SSID"] = ssidOverride
    env["OMAWIFI_BAND"] = bandPref
    return env
  }

  // ---- commands ------------------------------------------------------------
  // Flags first: the script accepts them on either side of the subcommand, and
  // putting them here keeps the subcommand the last word of the call.
  readonly property var commonArgs: {
    var args = []
    if (pinBand) args.push("--pin-band")
    if (simpleRanking) args.push("--simple")
    return args
  }

  // A read is disposable: if an action holds the radio, the next tick will do.
  function refresh(op) {
    // `ui` always answers; --all simply widens the list to both bands.
    var args = commonArgs.slice()
    args.push("ui")
    if (showAllBands) args.push("--all")
    helper.run(op || "ui", args, false)
  }

  // Actions are queued, not refused: a click that lands while a poll is in
  // flight must still happen, just after it.
  function act(op, args, message) {
    lastMessage = message
    actionFailed = false
    helper.run(op, args, true)
  }

  // A fresh scan takes a second or two and briefly interrupts the link, so it
  // is the one read that is never fired by a timer.
  function scan() {
    lastMessage = "Scanning…"
    actionFailed = false
    helper.run("ui", commonArgs.concat(["ui"]), true)
  }

  function bind(bssid) {
    act("bind", commonArgs.concat(["bind", bssid]), "Anchoring " + bssid + "…")
  }

  function anchorBest() {
    act("switch", commonArgs, "Anchoring to the best access point…")
  }

  function clearAnchor() {
    act("auto", commonArgs.concat(["auto"]), "Dropping the anchor…")
  }

  Helper {
    id: helper
    script: root.scriptPath
    environment: root.scriptEnv

    onFinished: function (op, code, out, err) {
      if (op === "ui") {
        var parsed = M.parse(out)
        if (parsed) {
          root.doc = parsed
          root.errorText = parsed.ok === false ? String(parsed.error || "") : ""
        } else if (code !== 0) {
          root.errorText = M.actionMessage(op, code, out, err)
        }
        // A refresh never overwrites the footer: it is not something the user
        // asked for, and it lands every few seconds.
        return
      }
      root.lastMessage = M.actionMessage(op, code, out, err)
      root.actionFailed = code !== 0
      // The link needs a moment to settle before a read is true, and a bind
      // that reported success still has to be re-read to show the new anchor.
      settleTimer.restart()
    }
  }

  // ---- front page ----------------------------------------------------------
  readonly property bool panelOpen: panelLoader.item ? panelLoader.item.opened === true : false

  // Poll for drift: the point of an anchor is that it can slip, and a whole read
  // is two nmcli calls. Slower while the panel is closed.
  Timer {
    id: closedPoll
    interval: root.refreshSeconds * 1000
    running: !root.panelOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  Timer {
    id: openPoll
    interval: root.openRefreshSeconds * 1000
    running: root.panelOpen
    repeat: true
    onTriggered: root.refresh()
  }

  // Two reads after an action: the first as soon as the link answers again, the
  // second to catch a bind that reports success a beat before the radio has
  // actually moved.
  Timer {
    id: settleTimer
    interval: 900
    repeat: false
    onTriggered: { root.refresh(); Qt.callLater(function () { root.refresh() }) }
  }

  Component.onCompleted: root.refresh()

  // ---- panel ---------------------------------------------------------------
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("widget" in target) target.widget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing:
    panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root, direction)
    return false
  }

  onBarChanged: root.injectPanel()
  onSettingsChanged: root.injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // Hotkey and CLI route: `omarchy-shell io.github.hectorhache.omawifi toggle`.
  IpcHandler {
    target: "io.github.hectorhache.omawifi"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
    function scan(): void { root.scan() }
    function anchorBest(): void { root.anchorBest() }
    function clearAnchor(): void { root.clearAnchor() }
  }

  // ---- bar face ------------------------------------------------------------
  // Mark and number are two slots side by side, the same shape the Wi-Fi widgets
  // around it use. BarIconButton pins itself to exactly one glyph slot, so the
  // number rides in its own measured button rather than being drawn over the
  // neighbour. TextMetrics measures the number without rendering it, which keeps
  // the measurement from depending on the layout it is measuring for.
  readonly property bool labelShown: root.faceText !== "" && !root.vertical

  TextMetrics {
    id: faceMetrics
    font.family: labelButton.fontFamily
    font.pixelSize: labelButton.fontSize
    text: root.faceText
  }

  implicitWidth: widgetRow.implicitWidth
  implicitHeight: widgetRow.implicitHeight

  Item {
    id: widgetRow
    anchors.fill: parent
    implicitWidth: button.implicitWidth + (root.labelShown ? labelButton.implicitWidth : 0)
    implicitHeight: root.barSize

    BarIconButton {
      id: button
      bar: root.bar
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: implicitWidth
      text: ""
      iconComponent: glyphComponent
      useActiveColor: false
      foreground: root.faceColor
      slotSize: Style.bar.iconSlot
      tooltipText: root.tooltipText
      onPressed: function (b) {
        if (b === Qt.MiddleButton) root.scan()
        else if (b === Qt.RightButton) root.anchorBest()
        else root.togglePanel()
      }
    }

    WidgetButton {
      id: labelButton
      bar: root.bar
      anchors.left: button.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: visible ? implicitWidth : 0
      visible: root.labelShown
      text: root.faceText
      labelVisible: true
      fontSize: Style.font.bodySmall
      horizontalMargin: 3
      foreground: root.faceColor
      useActiveColor: false
      tooltipText: root.tooltipText
      onPressed: function (b) {
        if (b === Qt.MiddleButton) root.scan()
        else if (b === Qt.RightButton) root.anchorBest()
        else root.togglePanel()
      }
    }
  }

  readonly property string tooltipText: root.errorText !== "" && !root.doc
    ? "Wi-Fi Anchor: " + root.errorText
    : M.tooltip(root.doc, root.ssidOverride)

  Component {
    id: glyphComponent
    Item {
      ApGlyph {
        anchors.centerIn: parent
        iconSize: Style.bar.iconCanvas
        color: root.faceColor
        state: root.state
      }
    }
  }
}
