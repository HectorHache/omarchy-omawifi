import QtQuick
import qs.Commons
import qs.Ui

// One access point of the network.
//
// The row is a fixed-column table: a marker slot, the signal bars, the band, the
// BSSID, the channel, the rate, and the ranking score. Every column is measured
// from hidden copies of the very same Text items the row renders, so the widths
// are the widths the text actually needs (a TextMetrics can come out a fraction
// narrow, and a fraction narrow is an ellipsis). Columns are fixed, not elastic,
// so they line up from row to row and the list can be read down a column.
//
// There is deliberately no text badge column. A fixed slot for "HERE · ANCHOR"
// is a hole in every row that carries neither, which is most of them. Two facts
// about a row do not need words here:
//
//   the row the radio is on   is highlighted, and its address is in the accent
//   the row it is anchored to carries the widget's own ring mark, at the left
//
// The row does not read `containsMouse` for its highlight: the panel owns the
// cursor, so hovering reports back (hovered) and the panel moves the cursor.
// That is what keeps exactly one row highlighted whether the mouse or the
// keyboard is driving.
CursorSurface {
  id: root

  property var ap: null
  property bool showScore: true
  property bool isBest: false
  property bool activateOnClick: true

  property color labelColor: Color.foreground
  property color mutedColor: Color.foreground
  property color accentColor: Color.accent

  signal activate()
  signal hovered()

  readonly property bool isCurrent: !!ap && ap.current === true
  readonly property bool isPinned: !!ap && ap.pinned === true
  readonly property string bandText: root.ap ? (root.ap.band === "5G" ? "5G" : "2G") : "5G"
  readonly property string chanText: root.ap && root.ap.chan ? "ch " + root.ap.chan : "ch 000"
  readonly property string bssidText: root.ap ? String(root.ap.bssid) : ""
  readonly property string rateText: {
    var rate = Number(root.ap && root.ap.rate)
    if (!isFinite(rate) || rate <= 0) return ""
    return rate >= 1000 ? (rate / 1000).toFixed(1) + " Gbit/s" : Math.round(rate) + " Mbit/s"
  }

  implicitHeight: Style.space(30)
  radius: Style.cornerRadius
  clip: true
  current: root.isCurrent

  readonly property real inset: Style.space(10)
  readonly property real gap: Style.space(8)

  // ---- measurements --------------------------------------------------------
  // Hidden and therefore never painted; they exist only to be measured.
  SignalBars { id: barsMetrics; visible: false; strength: 1 }
  ApGlyph { id: markMetrics; visible: false; iconSize: Style.font.caption }
  Text {
    id: bandMetrics
    visible: false
    text: "5G"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Text {
    id: bssidMetrics
    visible: false
    text: "FF:FF:FF:FF:FF:FF"
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }
  Text {
    id: chanMetrics
    visible: false
    text: "ch 000"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Text {
    id: rateMetrics
    visible: false
    text: "1.2 Gbit/s"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Text {
    id: scoreMetrics
    visible: false
    text: "000"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  readonly property real markWidth: markMetrics.implicitWidth
  readonly property real scoreWidth: scoreMetrics.implicitWidth
  // The score column is only there when it is switched on, and a Row skips items
  // that are not visible, so the measurement has to skip it too.
  readonly property real scoreColumnWidth: root.showScore ? scoreWidth + gap : 0

  // The width the columns occupy without the row's own insets, and the width the
  // whole row needs with them. The panel sizes itself from the second; the spacer
  // inside the row is the difference between the first and what the row was
  // given. Mixing the two is how the score column ends up one inset pair past the
  // right edge, where it is clipped and never seen.
  readonly property real columnsWidth: markWidth + gap
                                        + barsMetrics.implicitWidth + gap
                                        + bandMetrics.implicitWidth + gap
                                        + bssidMetrics.implicitWidth + gap
                                        + chanMetrics.implicitWidth + gap
                                        + rateMetrics.implicitWidth + gap
                                        + scoreColumnWidth
  readonly property real naturalWidth: inset * 2 + columnsWidth

  // ---- the table ------------------------------------------------------------
  readonly property alias rowItem: row
  Row {
    id: row
    anchors.left: parent.left
    anchors.leftMargin: root.inset
    anchors.right: parent.right
    anchors.rightMargin: root.inset
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.gap

    // The mark, for the access point the radio is anchored to. Nothing else uses
    // this slot, so an unanchored row is indented by a mark's width and nothing
    // more.
    Item {
      width: root.markWidth
      height: root.markWidth
      anchors.verticalCenter: parent.verticalCenter

      ApGlyph {
        anchors.centerIn: parent
        visible: root.isPinned
        iconSize: root.markWidth
        color: root.isCurrent ? root.accentColor : root.labelColor
        state: root.isPinned ? "locked" : "roaming"
      }
    }

    SignalBars {
      anchors.verticalCenter: parent.verticalCenter
      strength: root.ap ? Number(root.ap.signal) / 100 : 0
      color: root.isCurrent ? root.accentColor : root.labelColor
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: bandMetrics.implicitWidth
      text: root.bandText
      color: root.mutedColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: bssidMetrics.implicitWidth
      text: root.bssidText
      color: root.isCurrent ? root.accentColor : root.labelColor
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: chanMetrics.implicitWidth
      text: root.ap && root.ap.chan ? root.chanText : ""
      color: root.mutedColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: rateMetrics.implicitWidth
      text: root.rateText
      color: root.mutedColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    // Absorbs whatever the row is given beyond the width its columns need, which
    // is what pins the score to the edge without making any column elastic. The
    // row and the insets cancel out, so this is the row width minus what the
    // columns occupy.
    Item {
      width: Math.max(0, row.width - root.columnsWidth)
      height: 1
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: root.scoreWidth
      visible: root.showScore && !!root.ap
      text: root.ap ? String(root.ap.score) : ""
      color: root.isBest ? root.accentColor : root.mutedColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activateOnClick ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton
    onContainsMouseChanged: if (containsMouse) root.hovered()
    onClicked: if (root.activateOnClick) root.activate()
  }
}
