import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// PlugPatcher bar button + popup. Lists the user's shell plugins and drives the
// `plugpatcher` CLI: patch a plugin into a git repo, track and update it, open
// it, send a pull request, or switch back to the original.
Panel {
  id: root
  moduleName: "io.github.mxkeaton.plugpatcher"
  ipcTarget: "io.github.mxkeaton.plugpatcher"

  readonly property string home: Quickshell.env("HOME")
  // The CLI ships inside the plugin (bin/plugpatcher) so a plain
  // `omarchy plugin add` works with no setup step. Falls back to a CLI on PATH.
  readonly property string bundledCli: {
    var u = String(Qt.resolvedUrl("bin/plugpatcher"))
    if (u.indexOf("file://") === 0) u = decodeURIComponent(u.substring(7))
    return u
  }
  readonly property string pathCli: home + "/.local/bin/plugpatcher"
  property string cli: bundledCli
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
  property string pendingDelete: ""   // plugin id whose delete prompt is open
  property string pendingPr: ""       // plugin id whose PR options are open
  property string sortBy: "edits"      // edits | name | id
  property string lastStdout: ""
  property string lastStderr: ""
  property string feedback: ""        // result shown in the feedback box
  property bool feedbackError: false
  property string progress: ""        // text shown while an action runs
  property string lastAction: ""      // verb of the running/last action
  property string lastActionId: ""    // plugin id of the running/last action
  property bool cancelRequested: false // user aborted an in-flight PR
  readonly property bool feedbackIsUrl: /^https?:\/\//.test(feedback)
  readonly property bool feedbackIsPr: /\/pull\/\d+/.test(feedback)
  property bool cliAvailable: true
  property bool settingsOpen: false
  property string picking: ""          // "" | "harness" | "model"
  property bool pendingConfigChange: false
  property var settings: ({ harness: "default", model: "", command: "", harnesses: [], models: [] })

  // Scrollbar geometry: barW is the visible width; barPush slides it right into
  // the panel's padding so it uses that space instead of leaving a gap.
  readonly property int barW: Style.space(18)
  readonly property int barPush: 0

  Component.onCompleted: cliCheck.running = true

  // The CLI lives outside the plugin, so make sure it exists before actions.
  Process {
    id: cliCheck
    // Prefer the CLI bundled in the plugin; fall back to one on PATH.
    command: ["bash", "-c",
      "for p in \"$1\" \"$2\"; do if [ -x \"$p\" ]; then printf '%s' \"$p\"; exit 0; fi; done; exit 1",
      "bash", root.bundledCli, root.pathCli]
    stdout: StdioCollector { id: cliOut; waitForEnd: true; onStreamFinished: { var p = String(cliOut.text).trim(); if (p !== "") root.cli = p } }
    onExited: function(code) { root.cliAvailable = code === 0; if (root.cliAvailable) root.loadSettings() }
  }

  function cmpPlugins(a, b) {
    var key = sortBy
    if (key === "id") return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0)
    if (key === "edits") return (b.lastEdit || 0) - (a.lastEdit || 0)
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

  function openUrl(u) {
    var s = String(u || "")
    if (s === "") return
    urlProc.command = [cli, "open-url", s]
    urlProc.running = true
  }

  function progressFor(args) {
    var a = String(args[0] || "")
    if (a === "setup") return "Setting up editing…"
    if (a === "sync") return "Updating from origin…"
    if (a === "pr") {
      if (String(args[2] || "") === "manual") return "Pushing and opening the GitHub PR page…"
      return "Pushing and writing the PR description… (this can take a moment)"
    }
    if (a === "pr-cancel") return "Closing the pull request…"
    if (a === "revert") return "Reverting to the original…"
    if (a === "delete") return "Deleting…"
    if (a === "use" || a === "switch") return "Switching install…"
    if (a === "open") return "Opening…"
    if (a === "update-all") return "Opening a terminal…"
    if (a === "editor") return "Opening the editor…"
    if (a === "files") return "Opening the folder…"
    return "Working…"
  }

  function runAction(args) {
    if (busy) return
    if (!cliAvailable) {
      feedbackError = true
      feedback = "plugpatcher CLI not found at " + cli
      return
    }
    pendingConfigChange = false
    busy = true
    lastAction = String(args[0] || "")
    lastActionId = String(args[1] || "")
    progress = progressFor(args)
    feedback = ""
    feedbackError = false
    lastStdout = ""
    lastStderr = ""
    statusMessage = progress
    actionProc.command = [cli].concat(args)
    actionProc.running = true
  }

  function shortId(id) {
    var h = 0, s = String(id)
    for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0
    return h.toString(16)
  }

  onOpenedChanged: if (opened) refresh()
  onSettingsOpenChanged: if (settingsOpen) { cliCheck.running = true; loadSettings() }

  function loadSettings() {
    settingsProc.running = true
  }

  function stateLabel(p) {
    if (!p) return ""
    if (p.state === "orphaned") return "orphaned"
    if (p.state === "editing") return p.cloneEnabled ? "patched" : "original"
    return "original"
  }

  function stateColor(p) {
    if (!p) return root.muted
    if (p.state === "orphaned") return root.danger
    if (p.state === "editing" && p.cloneEnabled) return Color.accent
    return root.muted
  }

  // Colour by label, not by slot: 'patched' is always accent, 'original' always
  // muted.
  function badgeColorFor(label) {
    return label === "patched" ? Color.accent : root.muted
  }

  function labelFor(options, value) {
    var list = options || []
    for (var i = 0; i < list.length; i++)
      if (String(list[i].value) === String(value)) return list[i].label
    if (value === undefined || value === null || value === "")
      return list.length > 0 ? list[0].label : "Default"
    return String(value)
  }

  function parseSettings(raw) {
    try { settings = JSON.parse(String(raw || "")) }
    catch (e) { settings = { harness: "default", model: "", command: "", harnesses: [], models: [] } }
  }

  function setConfig(key, value) {
    if (busy) return
    pendingConfigChange = true
    busy = true
    feedback = ""
    feedbackError = false
    statusMessage = "saving " + key + "…"
    actionProc.command = [cli, "config", key, String(value)]
    actionProc.running = true
  }

  Process {
    id: settingsProc
    command: [root.cli, "settings"]
    stdout: StdioCollector {
      id: settingsOut
      waitForEnd: true
      onStreamFinished: root.parseSettings(settingsOut.text)
    }
  }

  Process {
    id: listProc
    command: [root.cli, "heal"]
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.statusMessage = "refresh failed (exit " + code + ")"
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
    id: urlProc
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true; onStreamFinished: root.lastStdout = actionOut.text }
    stderr: StdioCollector { id: actionErr; waitForEnd: true; onStreamFinished: root.lastStderr = actionErr.text }
    onExited: function(code) {
      // Let the stream collectors finish before reading their text.
      Qt.callLater(function() {
        root.busy = false
        if (root.cancelRequested) {
          root.cancelRequested = false
          // Close a PR the aborted run may already have opened.
          root.runAction(["pr-cancel", root.lastActionId])
          return
        }
        var out = String(root.lastStdout || "").trim()
        var err = String(root.lastStderr || "").trim()
        if (code === 0) {
          // Surface stdout when there is something worth showing (e.g. a PR URL).
          root.feedbackError = false
          root.feedback = out
          root.progress = ""
          root.statusMessage = ""
        } else {
          root.feedbackError = true
          var lines = err.split("\n").filter(function(l) { return l.trim() !== "" })
          var msg = lines.length > 0 ? lines[lines.length - 1] : ("failed (exit " + code + ")")
          root.feedback = String(msg).replace(/^plugpatcher:\s*(error:\s*)?/, "")
          root.progress = ""
          root.statusMessage = "failed"
        }
        if (root.pendingConfigChange) {
          root.pendingConfigChange = false
          root.loadSettings()
        } else {
          root.refresh()
        }
      })
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
    id: badgeRoot
    property string label: ""
    property color textColor: root.muted
    property real factor: 1
    // When set, the pill is sized to this text instead of `label`, so different
    // words render as the same-size badge.
    property string widthRef: ""

    readonly property int textPx: Math.max(8, Math.round(Style.font.caption * factor))

    TextMetrics {
      id: badgeMetrics
      font.family: root.ff
      font.pixelSize: badgeRoot.textPx
      font.bold: true
      text: badgeRoot.widthRef !== "" ? badgeRoot.widthRef : badgeRoot.label
    }

    implicitWidth: badgeMetrics.width + Style.space(12 * factor)
    implicitHeight: badgeText.implicitHeight + Style.space(4 * factor)
    radius: height / 2
    color: Util.alpha(root.fg, 0.06)
    border.width: 1
    border.color: Util.alpha(textColor, 0.35)
    Text {
      id: badgeText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: badgeRoot.label
      color: badgeRoot.textColor
      font.family: root.ff
      font.pixelSize: badgeRoot.textPx
      font.bold: true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\udb85\udcd9"
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
          implicitHeight: Math.max(title.implicitHeight + subtitle.implicitHeight + Style.space(3), headerButtons.implicitHeight)

          Text {
            id: title
            text: "\udb85\udcd9  PlugPatcher"
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
            text: root.settingsOpen
                  ? "Configure how the AI button opens projects"
                  : (root.busy ? root.statusMessage
                               : (root.plugins.length + " plugins · patch, update, and share plugin edits"))
            color: root.muted
            font.family: root.ff
            font.pixelSize: Style.font.caption
            anchors.left: parent.left
            anchors.top: title.bottom
            anchors.topMargin: Style.space(3)
            elide: Text.ElideRight
            width: parent.width - headerButtons.width - Style.space(8)
          }

          Row {
            id: headerButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              id: settingsButton
              text: "\uf013"
              foreground: root.settingsOpen ? Color.accent : root.fg
              fontFamily: root.ff
              fontSize: Style.font.body
              bordered: true
              enabled: !root.busy
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              tooltipText: "Settings"
              onClicked: root.settingsOpen = !root.settingsOpen
            }

            Button {
              id: refreshButton
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
        }

        PanelSeparator { foreground: Util.alpha(root.fg, 0.15) }

        // ---------------------------------------------------------- toolbar
        Item {
          visible: !root.settingsOpen
          width: parent.width
          implicitHeight: Math.max(sortRow.implicitHeight, updatePluginsButton.implicitHeight)

          Row {
            id: sortRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
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
                { key: "edits", label: "Patched" },
                { key: "name", label: "Name" },
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

          ActionButton {
            id: updatePluginsButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Update Plugins"
            onClicked: root.runAction(["update-all"])
          }
        }

        // ---------------------------------------------------------- feedback
        Rectangle {
          id: feedbackBox
          visible: !root.settingsOpen && (root.busy ? root.progress !== "" : root.feedback !== "")
          width: parent.width
          implicitHeight: feedbackColumn.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: root.feedbackError ? Util.alpha(root.danger, 0.14) : Util.alpha(Color.accent, 0.12)
          border.width: 1
          border.color: root.feedbackError ? Util.alpha(root.danger, 0.55) : Util.alpha(Color.accent, 0.4)

          Column {
            id: feedbackColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(6)

            Text {
              id: feedbackText
              textFormat: Text.PlainText
              text: root.busy
                    ? "\uf110  " + root.progress
                    : ((root.feedbackError ? "\uf071  " : "\uf00c  ") + root.feedback)
              color: (!root.busy && root.feedbackIsUrl) ? Color.accent
                     : (root.feedbackError ? root.danger : root.fg)
              font.family: root.ff
              font.pixelSize: Style.font.bodySmall
              font.underline: !root.busy && root.feedbackIsUrl
              wrapMode: Text.WordWrap
              width: parent.width

              MouseArea {
                anchors.fill: parent
                visible: !root.busy && root.feedbackIsUrl
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openUrl(root.feedback)
              }
            }

            Row {
              spacing: Style.space(6)

              // While the PR is being created: abort it.
              ActionButton {
                visible: root.busy && root.lastAction === "pr" && root.lastActionId !== ""
                text: "Cancel PR"
                onClicked: {
                  root.cancelRequested = true
                  actionProc.running = false
                }
              }

              // After it finished: close the PR that was created.
              ActionButton {
                visible: !root.busy && root.feedbackIsPr
                text: "Cancel PR"
                onClicked: root.runAction(["pr-cancel", root.lastActionId])
              }

              ActionButton {
                visible: !root.busy
                text: "Dismiss"
                onClicked: root.feedback = ""
              }
            }
          }
        }

        // ---------------------------------------------------------- settings
        Column {
          visible: root.settingsOpen && root.picking === ""
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: "AI"
            color: root.muted
            font.family: root.ff
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Button {
            width: parent.width
            leftAlign: true
            text: "AI harness:  " + root.labelFor(root.settings.harnesses, root.settings.harness)
            foreground: root.fg
            fontFamily: root.ff
            fontSize: Style.font.body
            bordered: true
            enabled: !root.busy
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(6)
            onClicked: root.picking = "harness"
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.muted
            font.family: root.ff
            font.pixelSize: Style.font.caption
            text: root.settings.harness === "custom"
                  ? "Custom command: set with  plugpatcher config command \"<cmd>\"   ({dir} = repo path)"
                  : "What the AI button opens, inside each plugin's repo. The default agent runs inside Herdr."
          }
        }

        // ---------------------------------------------------------- picker
        Column {
          visible: root.settingsOpen && root.picking !== ""
          width: parent.width
          spacing: Style.space(10)

          Row {
            spacing: Style.space(8)

            Button {
              text: "\uf060  Back"
              foreground: root.fg
              fontFamily: root.ff
              fontSize: Style.font.bodySmall
              bordered: true
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(4)
              onClicked: root.picking = ""
            }

            Text {
              text: "Choose harness"
              color: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Item {
            width: parent.width
            height: Math.min(pickColumn.implicitHeight, Style.space(430))

            Flickable {
              id: pickFlick
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width - (root.barW + Style.space(6) - root.barPush)
              contentWidth: width
              contentHeight: pickColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: pickColumn
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: root.settings.harnesses || []

                  Button {
                    required property var modelData
                    width: pickColumn.width
                    leftAlign: true
                    text: modelData.label
                    selected: String(modelData.value) === String(root.settings.harness)
                    foreground: root.fg
                    fontFamily: root.ff
                    fontSize: Style.font.body
                    bordered: true
                    enabled: !root.busy
                    horizontalPadding: Style.space(10)
                    verticalPadding: Style.space(5)
                    onClicked: {
                      var target = root.picking
                      root.setConfig(target, modelData.value)
                      root.picking = ""
                    }
                  }
                }
              }
            }

            PlugScrollBar {
              id: pickBar
              z: 5
              width: root.barW
              anchors.right: parent.right
              anchors.rightMargin: -root.barPush
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              flickable: pickFlick
              foreground: root.fg
            }
          }
        }

        // ---------------------------------------------------------- list
        Item {
          id: listArea
          visible: !root.settingsOpen
          width: parent.width
          height: Math.min(pluginColumn.implicitHeight, Style.space(470))

        Flickable {
          id: listFlick
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: parent.width - (root.barW + Style.space(6) - root.barPush)
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

                    // name (the switch column floats over the card, top-right)
                    Item {
                      width: parent.width
                      implicitHeight: nameText.implicitHeight

                      Text {
                        id: nameText
                        textFormat: Text.PlainText
                        text: modelData.name || modelData.id
                        color: root.fg
                        font.family: root.ff
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width - switchCol.width - Style.space(10)
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.state === "editing"
                            ? (modelData.id + "  →  " + modelData.editId)
                            : (modelData.state === "orphaned"
                               ? (modelData.id + "  →  " + modelData.editId + "   (original removed)")
                               : modelData.id)
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
                        visible: modelData.state === "original"
                        text: "Patch"
                        foreground: Color.accent
                        onClicked: root.runAction(["setup", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "original" && !!modelData.source
                        text: "Source"
                        onClicked: root.runAction(["source", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing" || modelData.state === "orphaned"
                        text: "AI"
                        onClicked: root.runAction(["open", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing" || modelData.state === "orphaned"
                        text: "Editor"
                        onClicked: root.runAction(["editor", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing" || modelData.state === "orphaned"
                        text: "Browse"
                        onClicked: root.runAction(["files", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing"
                        text: "Update"
                        onClicked: root.runAction(["sync", modelData.id])
                      }

                      ActionButton {
                        visible: (modelData.state === "editing" || modelData.state === "orphaned") && !!modelData.source
                        text: "Source"
                        onClicked: root.runAction(["source", modelData.id])
                      }

                      ActionButton {
                        visible: modelData.state === "editing" && root.pendingDelete !== modelData.id && root.pendingPr !== modelData.id
                        text: "Send PR"
                        onClicked: root.pendingPr = modelData.id
                      }

                      ActionButton {
                        visible: (modelData.state === "editing" || modelData.state === "orphaned") && root.pendingDelete !== modelData.id
                        text: "Delete"
                        foreground: root.danger
                        onClicked: root.pendingDelete = modelData.id
                      }
                    }

                    // PR options
                    Row {
                      visible: modelData.state === "editing" && root.pendingPr === modelData.id
                      spacing: Style.space(6)

                      Text {
                        textFormat: Text.PlainText
                        text: "PR:"
                        color: root.muted
                        font.family: root.ff
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      ActionButton {
                        text: "Manual PR"
                        onClicked: {
                          var t = modelData.id
                          root.pendingPr = ""
                          root.runAction(["pr", t, "manual"])
                        }
                      }

                      ActionButton {
                        text: "AI PR"
                        onClicked: {
                          var t = modelData.id
                          root.pendingPr = ""
                          root.runAction(["pr", t, "ai"])
                        }
                      }

                      ActionButton {
                        text: "Cancel"
                        onClicked: root.pendingPr = ""
                      }
                    }

                    // delete prompt
                    Row {
                      visible: (modelData.state === "editing" || modelData.state === "orphaned") && root.pendingDelete === modelData.id
                      spacing: Style.space(6)

                      Text {
                        textFormat: Text.PlainText
                        text: "Delete:"
                        color: root.danger
                        font.family: root.ff
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      ActionButton {
                        visible: modelData.state !== "orphaned"
                        text: "Original"
                        foreground: root.danger
                        onClicked: {
                          var t = modelData.id
                          root.pendingDelete = ""
                          root.runAction(["delete", t, "original"])
                        }
                      }

                      ActionButton {
                        text: "Patched"
                        foreground: root.danger
                        onClicked: {
                          var t = modelData.id
                          root.pendingDelete = ""
                          root.runAction(["delete", t, "patched"])
                        }
                      }

                      ActionButton {
                        text: "Both"
                        foreground: root.danger
                        onClicked: {
                          var t = modelData.id
                          root.pendingDelete = ""
                          root.runAction(["delete", t, "both"])
                        }
                      }

                      ActionButton {
                        text: "Cancel"
                        onClicked: root.pendingDelete = ""
                      }
                    }
                  }

                  // Switch column: floats at the card's top-right, aligned with
                  // the name, and does not affect the content's spacing.
                  Column {
                    id: switchCol
                    z: 1
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(12)
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(10)
                    spacing: Style.space(2)

                    Badge {
                      anchors.horizontalCenter: parent.horizontalCenter
                      widthRef: "original"
                      label: root.stateLabel(modelData)
                      textColor: root.stateColor(modelData)
                    }

                    Text {
                      visible: modelData.state === "editing"
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "\uf063"
                      color: root.muted
                      font.family: root.ff
                      font.pixelSize: Style.font.caption
                    }

                    Badge {
                      id: otherBadge
                      visible: modelData.state === "editing"
                      anchors.horizontalCenter: parent.horizontalCenter
                      factor: 2 / 3
                      widthRef: "original"
                      label: modelData.cloneEnabled ? "original" : "patched"
                      textColor: root.badgeColorFor(modelData.cloneEnabled ? "original" : "patched")

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAction(["use", modelData.id, "toggle"])
                      }
                    }
                  }
                }
              }
            }
          }

        }

          PlugScrollBar {
            id: listBar
            z: 5
            width: root.barW
            anchors.right: parent.right
            anchors.rightMargin: -root.barPush
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            flickable: listFlick
            foreground: root.fg
          }
        }
      }
    }
  }
}
