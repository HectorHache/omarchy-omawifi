import QtQuick
import qs.Commons

// The mark this widget is known by, drawn from primitives rather than from a
// font glyph.
//
// Two reasons. The bar already carries Omarchy's own Wi-Fi indicator, so a
// second signal-fan glyph beside it would read as a duplicate of the link
// indicator. And the anchor's whole job is "which access point does this radio
// hold", which a picture answers better than an arc: a ring is the anchor, the
// dot inside it is the radio.
//
// The dot's position is the state, so the bar reads at a glance without colour:
//   locked   centred   — the radio is on the access point you anchored to
//   drifted  pushed to the edge — it slipped off it
//   roaming  hollow    — nothing is anchored, NetworkManager chooses
//   offline  no dot    — not associated
Item {
  id: root

  property real iconSize: Style.space(14)
  property color color: Color.foreground
  property string state: "offline"      // locked | drifted | roaming | offline
  property real ringWidth: Math.max(1, Math.round(iconSize * 0.085))

  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property bool _dims: root.state === "offline"

  Rectangle {
    id: ring
    anchors.centerIn: parent
    width: root.iconSize
    height: root.iconSize
    radius: width / 2
    color: "transparent"
    border.width: root.ringWidth
    border.color: root.color
    opacity: root._dims ? 0.45 : 1
  }

  Rectangle {
    id: dot
    readonly property real dotSize: Math.max(3, Math.round(root.iconSize * 0.3))
    width: dotSize
    height: dotSize
    radius: dotSize / 2
    border.width: root.state === "roaming" ? root.ringWidth : 0
    border.color: root.color
    color: root.state === "roaming" ? "transparent" : root.color
    opacity: root._dims ? 0.45 : 1
    // Off-centre is the drift: half the radius in from the middle, towards the
    // ring, which is as far as it can go without leaving the mark.
    x: (root.width - width) / 2 + (root.state === "drifted" ? root.iconSize * 0.3 : 0)
    y: (root.height - height) / 2
    visible: root.state !== "offline"
  }
}
