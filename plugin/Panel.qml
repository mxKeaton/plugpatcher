import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// PlugPatcher bar button + popup. Lists the user's shell plugins and drives the
// `plugpatcher` CLI: set up editing, sync upstream, open a PR, remove, or open
// the project in the default coding agent.
Panel {
  id: root
  moduleName: "plugpatcher"
  ipcTarget: "plugpatcher"

  readonly property string home: Quickshell.env("HOME")
  readonly property string cli: home + "/.local/bin/plugpatcher"
  readonly property string catalogPath: home + "/.local/share/plugpatcher/catalog.json"

  property var plugins: []
  property bool busy: false
  property string statusMessage: ""

  // Safe accessors: `bar` is injected by the host and can briefly be null
  // while the panel is being built.
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string ff: bar ? bar.fontFamily : Style.font.family

  function reload() {
    if (!busy && !catalogProc.running) catalogProc.running = true
  }

  function refresh() {
    if (busy || listProc.running) return
    listProc.running = true
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

  function stateLabel(p) {
    if (p.state === "editing") return p.editId ? ("editing → " + p.editId) : "editing"
    return "original"
  }

  onOpenedChanged: if (opened) refresh()

  // Refresh: regenerate the catalog via the CLI, then read it.
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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
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
    contentWidth: panel.fittedContentWidth(Style.space(560))
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

        // ---------------- hero ----------------
        Item {
          width: parent.width
          implicitHeight: Math.max(title.implicitHeight, subtitle.implicitHeight) + Style.space(4)

          Text {
            id: title
            text: "PlugPatcher"
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
            text: root.busy ? root.statusMessage : (root.plugins.length + " user plugins")
            color: Qt.darker(root.fg, 1.4)
            font.family: root.ff
            font.pixelSize: Style.font.caption
            anchors.left: parent.left
            anchors.top: title.bottom
            anchors.topMargin: Style.space(2)
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
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(3)
            onClicked: root.refresh()
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------------- plugin list ----------------
        Flickable {
          width: parent.width
          height: Math.min(pluginColumn.implicitHeight, Style.space(430))
          contentWidth: width
          contentHeight: pluginColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: pluginColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.plugins

              Item {
                required property var modelData
                width: pluginColumn.width
                implicitHeight: rowColumn.implicitHeight

                Column {
                  id: rowColumn
                  width: parent.width
                  spacing: Style.space(3)

                  Text {
                    text: modelData.name || modelData.id
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.id + "  ·  " + root.stateLabel(modelData)
                    color: Qt.darker(root.fg, 1.5)
                    font.family: root.ff
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Row {
                    spacing: Style.space(6)

                    Button {
                      visible: modelData.state !== "editing"
                      text: "Set up editing"
                      foreground: root.fg
                      fontFamily: root.ff
                      fontSize: Style.font.bodySmall
                      bordered: true
                      enabled: !root.busy
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(3)
                      onClicked: root.runAction(["setup", modelData.id])
                    }

                    Button {
                      visible: modelData.state === "editing"
                      text: "Sync"
                      foreground: root.fg
                      fontFamily: root.ff
                      fontSize: Style.font.bodySmall
                      bordered: true
                      enabled: !root.busy
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(3)
                      onClicked: root.runAction(["sync", modelData.id])
                    }

                    Button {
                      visible: modelData.state === "editing"
                      text: "Open"
                      foreground: root.fg
                      fontFamily: root.ff
                      fontSize: Style.font.bodySmall
                      bordered: true
                      enabled: !root.busy
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(3)
                      onClicked: root.runAction(["open", modelData.id])
                    }

                    Button {
                      visible: modelData.state === "editing"
                      text: "PR"
                      foreground: root.fg
                      fontFamily: root.ff
                      fontSize: Style.font.bodySmall
                      bordered: true
                      enabled: !root.busy
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(3)
                      onClicked: root.runAction(["pr", modelData.id])
                    }

                    Button {
                      visible: modelData.state === "editing"
                      text: "Remove"
                      foreground: root.fg
                      fontFamily: root.ff
                      fontSize: Style.font.bodySmall
                      bordered: true
                      enabled: !root.busy
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(3)
                      onClicked: root.runAction(["remove", modelData.id])
                    }
                  }
                }

                PanelSeparator { width: parent.width; foreground: root.fg }
              }
            }
          }
        }
      }
    }
  }
}
