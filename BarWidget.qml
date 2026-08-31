import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Compact Chi-Rho in the bar. Service.qml stays mounted with the bar so the
// office for the current hour is always derived. Click/IPC contract matches
// the Liturgy of the Hours widget.
BarWidget {
  id: root
  moduleName: "io.github.whelanh.catholic-reference"

  Service {
    id: office
    settings: root.settings
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = office
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.whelanh.catholic-reference"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: !!office.currentHour
    tooltipText: office.tooltipText
    iconComponent: Component {
      ChiRho {
        anchors.fill: parent
        foreground: button.active && button.useActiveColor ? button.activeColor : button.foreground
        size: Math.min(width, height)
      }
    }

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.togglePanel()
    }
  }
}
