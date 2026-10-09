import QtQuick
import qs.Commons

// A draggable vertical scrollbar for a Flickable whose content is taller than
// its viewport. Drag the handle, or click the track to jump.
Item {
  id: root

  required property var flickable
  property color foreground: Color.foreground
  property real minHandleHeight: 28

  readonly property real trackHeight: height
  readonly property bool scrollable: flickable && flickable.contentHeight > flickable.height + 1
  readonly property real maxScroll: scrollable ? (flickable.contentHeight - flickable.height) : 0
  readonly property real handleHeight: scrollable
    ? Math.max(minHandleHeight, Math.min(trackHeight, trackHeight * (flickable.height / flickable.contentHeight)))
    : 0
  readonly property real handleY: {
    if (!scrollable) return 0
    var t = trackHeight - handleHeight
    if (t <= 0 || maxScroll <= 0) return 0
    return (flickable.contentY / maxScroll) * t
  }

  visible: scrollable
  implicitWidth: Style.space(14)

  Rectangle {
    id: track
    anchors.right: parent.right
    width: Math.round(root.width * 0.75)
    height: root.height
    color: Util.alpha(root.foreground, 0.08)
  }

  Rectangle {
    id: handle
    anchors.right: parent.right
    y: root.handleY
    width: track.width
    height: root.handleHeight
    color: Util.alpha(root.foreground, dragArea.pressed ? 0.6 : 0.38)
  }

  MouseArea {
    id: dragArea
    anchors.fill: parent
    preventStealing: true
    property real grabOffset: 0

    function scrollToViewportY(vy) {
      var t = root.trackHeight - root.handleHeight
      if (t <= 0) return
      var hy = Math.max(0, Math.min(t, vy - dragArea.grabOffset))
      root.flickable.contentY = Math.max(0, Math.min(root.maxScroll, (hy / t) * root.maxScroll))
    }

    onPressed: function(mouse) {
      var vy = dragArea.mapToItem(root.flickable, mouse.x, mouse.y).y
      var handleViewportY = root.flickable.contentY + root.handleY
      if (vy >= handleViewportY && vy <= handleViewportY + root.handleHeight) {
        dragArea.grabOffset = vy - handleViewportY
      } else {
        dragArea.grabOffset = root.handleHeight / 2
        dragArea.scrollToViewportY(vy)
      }
    }

    onPositionChanged: function(mouse) {
      if (!pressed) return
      var vy = dragArea.mapToItem(root.flickable, mouse.x, mouse.y).y
      dragArea.scrollToViewportY(vy)
    }
  }
}
