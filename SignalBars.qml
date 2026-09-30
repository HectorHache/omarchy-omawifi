import QtQuick
import qs.Commons

// Four bars, drawn rather than typed, so a row's strength reads the same in
// every theme and never depends on which Nerd Font glyph a machine happens to
// carry. Unreached bars stay visible at low alpha, which is what makes the
// difference between two access points legible at a glance.
Item {
  id: root

  property real strength: 0            // 0..1
  property color color: Color.foreground
  property int bars: 4
  property real barWidth: Math.max(2, Math.round(Style.space(2)))
  property real barGap: Math.max(1, Math.round(Style.spaceReal(1.4)))

  implicitWidth: bars * barWidth + (bars - 1) * barGap
  implicitHeight: Style.space(12)

  Repeater {
    model: root.bars

    Rectangle {
      required property int index
      // Shortest bar is a third of the height; the last one fills it.
      readonly property real share: 0.34 + 0.66 * (index / Math.max(1, root.bars - 1))
      width: root.barWidth
      height: Math.max(2, Math.round(root.implicitHeight * share))
      x: index * (root.barWidth + root.barGap)
      y: root.implicitHeight - height
      radius: Math.min(width / 2, Style.cornerRadius)
      color: ((index + 1) / root.bars) <= (root.strength + 0.001)
        ? root.color
        : Util.alpha(root.color, 0.22)

      Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    }
  }
}
