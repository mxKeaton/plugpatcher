import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// PlugPatcher bar button + popup. Lists the user's shell plugins and drives the
// `plugpatcher` CLI: patch a plugin, update it from upstream, open it, send a
// PR, or revert to the pristine original.
Panel {
  id: root
  moduleName: "plugpatcher"
  ipcTarget: "plugpatcher"

  readonly property string home: Quickshell.env("HOME")
  readonly property string cli: home + "/.local/bin/plugpatcher"
  readonly property string catalogPath: home + "/.local/share/plugpatcher/catalog.json"

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string ff: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Util.alpha(root.fg, 0.55)
  readonly property color cardBg: Util.alpha(root.fg, 0.05)
  readonly property color cardBorder: Util.alpha(root.fg, 0.12)
  readonly property color danger: "#e5484d"

  // The bar sizes the widget slot from these, not from the child button.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var plugins: []
  property bool busy: false
  property string statusMessage: ""
  property string pendingRevert: ""   // plugin id awaiting revert confirmation
  property string sortBy: "name"       // name | edits | updates | id

  function cmpPlugins(a, b) {
    var key = sortBy
    if (key === "id") return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0)
    if (key === "edits") return (b.lastEdit || 0) - (a.lastEdit || 0)
    if (key === "updates") return (b.lastUpdate || 0) - (a.lastUpdate || 0)
    var an = String(a.name || a.id).toLowerCase()
    var bn = String(b.name || b.id).toLowerCase()
    return an < bn ? -1 : (an > bn ? 1 : 0)
  }

  readonly property var sortedPlugins: {
    var list = (plugins || []).slice()
    list.sort(cmpPlugins)
    return list
  }

  function fmtDate(ts) {
    if (!ts) return "—"
    return Qt.formatDateTime(new Date(ts * 1000), "d MMM yyyy HH:mm")
  }

  function refresh() {
    if (busy) return
    // Show whatever catalog exists immediately, then regenerate it.
    reload()
    if (!listProc.running) listProc.running = true
  }

  function reload() {
    if (!busy && !catalogProc.running) catalogProc.running = true
  }

  function parseCatalog(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      plugins = Array.isArray(data.plugins) ? data.plugins : []
    } catch (e) {
      plugins = []
    }
  }

  function runAction(args) {
    if (busy) return
    busy = true
    statusMessage = args.join(" ") + " …"
    actionProc.command = [cli].concat(args)
    actionProc.running = true
  }

  function shortId(id) {
    var h = 0, s = String(id)
    for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0
    return h.toString(16)
  }

  onOpenedChanged: if (opened) refresh()

  Process {
    id: listProc
    command: [root.cli, "list"]
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.statusMessage = "list failed (exit " + code + ")"
      Qt.callLater(root.reload)
    }
  }

  Process {
    id: catalogProc
    command: ["cat", root.catalogPath]
    stdout: StdioCollector {
      id: catalogOut
      waitForEnd: true
      onStreamFinished: root.parseCatalog(catalogOut.text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      root.busy = false
      root.statusMessage = code === 0 ? "done" : ("failed (exit " + code + ")")
      root.refresh()
    }
  }

  component ActionButton: Button {
    foreground: root.fg
    fontFamily: root.ff
    fontSize: Style.font.bodySmall
    bordered: true
    enabled: !root.busy
    horizontalPadding: Style.space(8)
    verticalPadding: Style.space(3)
  }

  component Badge: Rectangle {
    property string label: ""
    property color textColor: root.muted
    implicitWidth: badgeText.implicitWidth + Style.space(12)
    implicitHeight: badgeText.implicitHeight + Style.space(4)
    radius: height / 2
    color: Util.alpha(root.fg, 0.06)
    border.width: 1
    border.color: Util.alpha(textColor, 0.35)
    Text {
      id: badgeText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: parent.label
      color: parent.textColor
      font.family: root.ff
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0ad"
    tooltipText: "PlugPatcher"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------------------------------------------------------- header
        Item {
          width: parent.width
          implicitHeight: Math.max(title.implicitHeight + subtitle.implicitHeight + Style.space(3), refreshButton.implicitHeight)

          Text {
            id: title
            text: "\uf0ad  PlugPatcher"
            color: root.fg
            font.family: root.ff
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.left: parent.left
            anchors.top: parent.top
          }

          Text {
            id: subtitle
            textFormat: Text.PlainText
            text: root.busy ? root.statusMessage
                            : (root.plugins.length + " plugins · patch without losing updates")
            color: root.muted
            font.family: root.ff
            font.pixelSize: Style.font.caption
            anchors.left: parent.left
            anchors.top: title.bottom
            anchors.topMargin: Style.space(3)
            elide: Text.ElideRight
            width: parent.width - refreshButton.width - Style.space(8)
          }

          Button {
            id: refreshButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Refresh"
            foreground: root.fg
            fontFamily: root.ff
            fontSize: Style.font.bodySmall
            bordered: true
            enabled: !root.busy
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(4)
            onClicked: root.refresh()
          }
        }

        PanelSeparator { foreground: Util.alpha(root.fg, 0.15) }

        // ---------------------------------------------------------- sort
        Row {
          spacing: Style.space(6)

          Text {
            text: "Sort"
            color: root.muted
            font.family: root.ff
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }

          Repeater {
            model: [
              { key: "name", label: "Name" },
              { key: "edits", label: "Last edits" },
              { key: "updates", label: "Last updates" },
              { key: "id", label: "ID" }
            ]

            ActionButton {
              required property var modelData
              text: modelData.label
              selected: root.sortBy === modelData.key
              onClicked: root.sortBy = modelData.key
            }
          }
        }

        // ---------------------------------------------------------- list
        Flickable {
          width: parent.width
          height: Math.min(pluginColumn.implicitHeight, Style.space(470))
          contentWidth: width
          contentHeight: pluginColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: pluginColumn
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.sortedPlugins

              Rectangle {
                required property var modelData
                width: pluginColumn.width
                implicitHeight: card.implicitHeight
                color: "transparent"

                Rectangle {
                  id: card
                  width: parent.width
                  implicitHeight: cardColumn.implicitHeight + Style.space(20)
                  radius: Style.cornerRadius
                  color: root.cardBg
                  border.width: 1
                  border.color: root.cardBorder

                  Column {
                    id: cardColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    spacing: Style.space(8)

                    // name + state badge
                    Item {
                      width: parent.width
                      implicitHeight: Math.max(nameText.implicitHeight, badge.implicitHeight)

                      Text {
                        id: nameText
                        textFormat: Text.PlainText
                        text: modelData.name || modelData.id
                        color: root.fg
                        font.family: root.ff
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width - badge.width - Style.space(10)
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Badge {
                        id: badge
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        label: modelData.state === "editing" ? "patched" : "original"
                        textColor: modelData.state === "editing" ? Color.accent : root.muted
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.state === "editing"
                            ? (modelData.id + "  →  " + modelData.editId)
                            : modelData.id
                      color: root.muted
                      font.family: root.ff
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }

                    Text {
                      visible: modelData.state === "editing"
                      textFormat: Text.PlainText
                      text: "edited " + root.fmtDate(modelData.lastEdit) + "   ·   updated " + root.fmtDate(modelData.lastUpdate)
                      color: Util.alpha(root.fg, 0.35)
                      font.family: root.ff
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }

                    // actions
                    Row {
                      spacing: Style.space(6)

                      ActionButton {
                        visible: modelData.state !== "editing"
                        text: "Patch"
                        foreground: Color.accent
                        onClicked: root.runAction(["setup", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing"
                        text: "Update origin"
                        onClicked: root.runAction(["sync", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing"
                        text: "Open"
                        onClicked: root.runAction(["open", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing"
                        text: "Editor"
                        onClicked: root.runAction(["editor", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing"
                        text: "Files"
                        onClicked: root.runAction(["files", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing" && root.pendingRevert !== modelData.id
                        text: "Send PR"
                        onClicked: root.runAction(["pr", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing" && root.pendingRevert !== modelData.id
                        text: "Revert"
                        foreground: root.danger
                        onClicked: root.pendingRevert = modelData.id
                      }
                    }

                    // revert confirmation
                    Row {
                      visible: modelData.state === "editing" && root.pendingRevert === modelData.id
                      spacing: Style.space(6)

                      Text {
                        textFormat: Text.PlainText
                        text: "Revert all edits and restore the original?"
                        color: root.danger
                        font.family: root.ff
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      ActionButton {
                        text: "Yes, revert"
                        foreground: root.danger
                        onClicked: {
                          var target = modelData.id
                          root.pendingRevert = ""
                          root.runAction(["revert", target])
                        }
                      }

                      ActionButton {
                        text: "Cancel"
                        onClicked: root.pendingRevert = ""
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
