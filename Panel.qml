import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as M

// Wi-Fi Anchor — the panel.
//
// Shows every access point of the network the machine is on, which one the
// radio holds, and lets you hold a different one. The action that matters
// (anchor to this access point) is one row click or one Enter away, because
// that is the whole reason the widget exists: the profile's BSSID is rewritten
// and the connection is brought back up, which takes a couple of seconds and
// drops the link while it happens.
//
// State comes from the bar widget (one script, one snapshot, one source of
// truth); the panel only formats it and asks for actions.
Panel {
  id: root
  moduleName: "io.github.hectorhache.omawifi"
  ipcTarget: "io.github.hectorhache.omawifi"
  // The bar widget owns the IPC route for this plugin, so this panel must not
  // register a second handler on the same target.
  manageIpc: false

  property var anchorItem: null
  property var widget: null

  // Held by access point, not by row: the list re-sorts whenever a scan lands,
  // and a cursor kept as an index would silently drift to a different access
  // point than the one under the highlight.
  property string cursorBssid: ""
  property bool cursorActive: false

  readonly property var doc: widget ? widget.doc : null
  readonly property var aps: doc && doc.aps ? doc.aps : []
  readonly property string state: doc ? String(doc.state || "offline") : "offline"
  readonly property bool busy: widget ? widget.busy === true : false
  readonly property bool show24: widget ? widget.showAllBands === true : false
  readonly property int cursorIndex: Math.max(0, M.indexOfBssid(root.aps, root.cursorBssid))

  // How wide the panel has to be, measured rather than guessed: the widest row
  // of the list, the keyboard hints, and the two header groups. Sizing this by
  // hand is how a column ends up truncated while the panel still has a band of
  // dead space beside it.
  //
  // `contentWidth` is the width of the whole card, content plus the card's own
  // padding and border, so the measurement here is the wanted content width and
  // the card's chrome is added on top. Getting that wrong by a padding's worth is
  // enough to push the last column of a row past the content area, where it is
  // clipped away and never drawn.
  readonly property string hintLeft: "up/down choose   enter anchor   b best"
  readonly property string hintRight: "r rescan   a release   esc close"
  TextMetrics {
    id: hintMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    text: "up/down choose   enter anchor   b best"
  }
  TextMetrics {
    id: hintMetrics2
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    text: "r rescan   a release   esc close"
  }
  // The status line changes with the state, and the longest one is the drift
  // message. Sizing the panel to it means the card settles on one width and
  // never resizes as the state moves between locked, drifted and roaming.
  TextMetrics {
    id: statusMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    text: "The radio moved off the anchored access point"
  }
  readonly property real contentNeeded: Math.max(
    rowMetrics.naturalWidth,
    Math.max(hintMetrics.width, hintMetrics2.width) + Style.space(6),
    statusMetrics.width + Style.space(17),
    headLeft.implicitWidth + headRight.implicitWidth + Style.space(24),
    actionRow.implicitWidth + Style.space(16))
  // The card's padding and border, uniform on every side, so the vertical inset
  // the panel already reports describes the horizontal one too.
  readonly property real neededWidth: root.contentNeeded + panel.verticalContentInset

  readonly property string fontFamily: Style.font.family
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  // The in-use access point's address is drawn in the theme accent so it reads
  // apart from the anchored ring: the two are the same row when locked and
  // different rows the moment the radio drifts.
  readonly property color accent: Color.accent
  // Blend towards the surface behind the panel instead of lowering alpha:
  // on a light theme, a foreground at low alpha over a bright surface reads
  // as "less important" only until it reads as "washed out".
  readonly property color surface: Color.popups.background
  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  readonly property color dim: mix(fg, surface, 0.38)
  readonly property color dimmer: mix(fg, surface, 0.58)

  // PanelHero uppercases this and adds wide letter spacing, which is why it
  // holds bare tokens ("5 GHZ · 95% · -42 DBM") and not a rate string: a unit
  // with a slash in it reads as shouted text at that size. The rate belongs to
  // the individual access point anyway, so it stays in the rows.
  readonly property string heroMeta: {
    if (!doc) return ""
    var on = M.firstWhere(aps, "current")
    var bits = []
    if (on) {
      bits.push(M.bandName(on.band))
      bits.push(M.signalText(doc))
    } else if (state === "offline") {
      bits.push("not associated")
    }
    if (doc.cached) bits.push("cached scan")
    return M.joinNonEmpty(bits, " · ")
  }

  function bindBssid(bssid) {
    if (!bssid || !root.widget) return
    root.widget.bind(String(bssid))
  }

  function moveCursor(dy) {
    if (root.aps.length === 0) return
    root.cursorActive = true
    var next = root.cursorIndex + dy
    if (next < 0) next = 0
    if (next > root.aps.length - 1) next = root.aps.length - 1
    root.cursorBssid = String(root.aps[next].bssid)
  }

  onOpenedChanged: {
    if (root.opened) {
      root.cursorBssid = M.initialBssid(root.doc)
      root.cursorActive = false
    }
  }

  // An access point that disappears from the list (out of range, band switch)
  // must not leave the cursor pointing at nothing.
  onApsChanged: {
    if (root.cursorBssid !== "" && M.indexOfBssid(root.aps, root.cursorBssid) < 0)
      root.cursorBssid = M.initialBssid(root.doc)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.neededWidth)
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    // Invisible, used only for its measured column widths.
    ApRow {
      id: rowMetrics
      visible: false
      width: 0
      ap: null
      showScore: root.widget ? root.widget.showScores === true : true
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While the radio is being repinned the panel is a status display, not a
      // control surface: the link is down and a second command would race the
      // first.
      blocked: root.busy

      onMoveRequested: function (dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.bindBssid(root.cursorBssid)
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (text, modifiers) {
        var key = String(text).toLowerCase()
        if (key === "r") root.widget.scan()
        else if (key === "b") root.widget.anchorBest()
        else if (key === "a") root.widget.clearAnchor()
        else if (key === "j") root.moveCursor(1)
        else if (key === "k") root.moveCursor(-1)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.lg

        // ---------------------------------------------------------------- hero
        PanelHero {
          width: parent.width
          iconComponent: heroGlyph
          title: String((root.widget && root.widget.ssidOverride) || (root.doc && root.doc.ssid) || "Wi-Fi")
          meta: root.heroMeta
          detail: M.stateTitle(root.state)
          foreground: root.fg
          fontFamily: root.fontFamily
          // No trailing rescan icon here on purpose: rescan is the labelled
          // button in the action row (and the "r" key, and a middle click on
          // the bar). A second icon-only copy in the header only added an
          // ambiguous glyph, so the header stays a pure status readout.
        }

        // ------------------------------------------------------------- state
        Row {
          spacing: Style.space(10)
          width: parent.width

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7)
            height: width
            radius: width / 2
            color: root.state === "locked" ? root.fg
              : root.state === "drifted" ? root.urgentColor
              : root.dimmer
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(17)
            text: root.busy && root.widget ? String(root.widget.lastMessage || "Working…") : M.stateLine(root.doc)
            color: root.busy && root.widget && root.widget.actionFailed ? root.urgentColor : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator { foreground: root.fg }

        // ------------------------------------------------------------ heading
        Item {
          width: parent.width
          height: Math.max(headLeft.implicitHeight, headRight.implicitHeight)

          Row {
            id: headLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "ACCESS POINTS"
              foreground: root.fg
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: M.countText(root.aps.length)
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              visible: text !== ""
              text: root.doc && root.doc.iface ? String(root.doc.iface) : ""
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: headRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "2.4 GHz"
              color: root.show24 ? root.fg : root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              checked: root.show24
              interactive: !root.busy
              foreground: root.fg
              trackHeight: Math.round(Style.spacing.controlHeight * 0.45)
              onToggled: {
                if (!root.widget) return
                root.widget.showAllBands = !root.widget.showAllBands
                root.widget.refresh()
              }
            }
          }
        }

        // ------------------------------------------------------------- list
        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.aps.length === 0
          text: root.doc && root.doc.ok === false
            ? String(root.doc.error || "Wi-Fi is not available")
            : (root.state === "offline"
              ? "No access point of this network is visible."
              : "No access point of this network is visible on this band.")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        ListView {
          id: apList
          width: parent.width
          visible: root.aps.length > 0
          height: Math.min(Style.space(320),
                           Math.max(1, root.aps.length) * (Style.space(30) + Style.space(2)))
          model: root.aps
          spacing: Style.space(2)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: root.cursorIndex
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: ApRow {
            width: apList.width
            ap: modelData
            isBest: index === 0
            showScore: root.widget ? root.widget.showScores === true : true
            hasCursor: String(modelData.bssid) === root.cursorBssid && root.cursorActive
            labelColor: root.fg
            mutedColor: root.dim
            accentColor: root.accent
            onHovered: { root.cursorBssid = String(modelData.bssid); root.cursorActive = true }
            onActivate: root.bindBssid(modelData.bssid)
          }
        }

        // Legend: the ring on a row is the anchored access point, an accent
        // address is the one in use. It wraps to the panel width rather than
        // widening the card, and it lays the drawn ring beside the first line
        // so the mark is explained by the mark, not by a font glyph.
        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.aps.length > 0

          ApGlyph {
            anchors.top: parent.top
            anchors.topMargin: Math.round(Style.font.caption * 0.15)
            iconSize: Style.font.body
            color: root.fg
            state: "locked"
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width - Style.font.body - Style.space(8)
            wrapMode: Text.WordWrap
            text: "the ring marks the access point you anchored to, and an address in the theme's accent colour is the one in use"
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------------------------------------------------------- actions
        Item {
          width: parent.width
          height: actionRow.implicitHeight

          Row {
            id: actionRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap

            Button {
              text: "Anchor to best"
              enabled: !root.busy && root.aps.length > 0
              fontSize: Style.font.bodySmall
              foreground: root.fg
              bordered: true
              onClicked: root.widget.anchorBest()
            }

            Button {
              text: "Release anchor"
              enabled: !root.busy && !!(root.doc && root.doc.pinned)
              fontSize: Style.font.bodySmall
              foreground: root.fg
              bordered: true
              onClicked: root.widget.clearAnchor()
            }

            Button {
              text: "Rescan"
              enabled: !root.busy
              fontSize: Style.font.bodySmall
              foreground: root.fg
              bordered: true
              onClicked: root.widget.scan()
            }
          }

        }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: root.hintLeft
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            text: root.hintRight
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // ---- pieces ---------------------------------------------------------------
  Component {
    id: heroGlyph
    Item {
      width: Style.font.displayLarge
      height: Style.font.displayLarge
      ApGlyph {
        anchors.centerIn: parent
        iconSize: Style.font.display
        color: root.state === "drifted" ? root.urgentColor : root.fg
        state: root.state
      }
    }
  }
}
