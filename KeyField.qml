import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A single-line search field built from key events instead of Qt's native
// editable text controls. Those controls connect to the system selection
// buffer's change signal while writable and, on every change, read offered
// foreign text with no byte or time bound; keeping this panel always mounted
// would let another application stall or exhaust the shared shell without a
// paste gesture. This field instantiates no native editor: it takes typed
// characters, Backspace and Return itself and draws the text with a plain
// Text. Modified chords (Ctrl/Alt/Meta) are ignored, so there is no paste.
Item {
  id: root

  property string text: ""
  property string placeholderText: ""
  property int maximumLength: 512
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.body
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  // Space kept clear on the right for an overlaid hint (e.g. "ENTER").
  property real rightReserve: 0

  signal edited()
  signal accepted()
  signal editingFinished()
  signal moveRequested(int delta)
  signal escapePressed()

  readonly property bool _hot: mouse.containsMouse
  readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

  // Typed text from a key event, or "" for anything that is not plain input.
  function typed(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return ""
    var value = String(event.text || "")
    for (var i = 0; i < value.length; i++) if (value.charCodeAt(i) < 32 || value.charCodeAt(i) === 127) return ""
    return value
  }

  activeFocusOnTab: true
  implicitWidth: Style.space(160)
  implicitHeight: label.implicitHeight + 2 * verticalPadding + Border.top(_borderSpec) + Border.bottom(_borderSpec)

  onActiveFocusChanged: if (!activeFocus) editingFinished()
  onTextChanged: edited()

  Keys.onPressed: function(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) {
      // Ctrl+Backspace / Ctrl+U clear, matching prior habits. Every other
      // modified chord is left unhandled so nothing maps to a paste.
      if (event.key === Qt.Key_Backspace || event.key === Qt.Key_U) {
        root.text = ""
        event.accepted = true
      }
      return
    }
    if (event.key === Qt.Key_Backspace) {
      root.text = root.text.slice(0, -1)
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      root.escapePressed()
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.moveRequested(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      root.moveRequested(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.accepted()
      root.editingFinished()
      event.accepted = true
    } else {
      var value = root.typed(event)
      if (value === "") return
      if (root.text.length < root.maximumLength) root.text = (root.text + value).slice(0, root.maximumLength)
      event.accepted = true
    }
  }

  BorderSurface {
    anchors.fill: parent
    color: Style.controlFill(root.activeFocus, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.cornerRadius
  }

  Item {
    id: inner
    anchors.fill: parent
    anchors.leftMargin: root.horizontalPadding + Border.left(root._borderSpec)
    anchors.rightMargin: root.rightReserve + root.horizontalPadding + Border.right(root._borderSpec)
    clip: true

    Text {
      id: label
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      // Long text keeps its end, where typing happens, in view.
      x: implicitWidth > inner.width ? inner.width - implicitWidth - caret.width : 0
      text: root.text !== "" ? root.text : root.placeholderText
      color: root.text !== "" ? root.foreground : Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }

    Rectangle {
      id: caret
      visible: root.activeFocus && blink.on
      x: root.text !== "" ? label.x + label.implicitWidth : label.x
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(1, Style.spaceReal(1))
      height: label.font.pixelSize * 1.2
      color: root.foreground
    }
  }

  Timer {
    id: blink
    property bool on: true
    interval: 530
    repeat: true
    running: root.activeFocus
    onRunningChanged: on = true
    onTriggered: on = !on
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.IBeamCursor
    onClicked: root.forceActiveFocus()
  }
}
