import QtQuick
import qs.Commons

// Chi-Rho (☧) Christogram: the superimposed Greek letters Chi (X) and Rho (P).
// Drawn as strokes so the bar can recolor it with the active theme, matching
// the Jerusalem Cross pattern in the Liturgy plugin.
Item {
  id: root
  property color foreground: Color.foreground
  property real size: 16

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    onPaint: {
      var ctx = getContext("2d")
      var s = Math.min(width, height)
      var cx = width / 2
      ctx.reset()
      ctx.strokeStyle = root.foreground
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      ctx.lineWidth = Math.max(1, s * 0.12)

      // Rho stem (vertical stroke).
      ctx.beginPath()
      ctx.moveTo(cx, s * 0.80)
      ctx.lineTo(cx, s * 0.22)
      ctx.stroke()

      // Rho loop (the P bowl, a right-hand semicircle over the stem top).
      ctx.beginPath()
      ctx.arc(cx, s * 0.22, s * 0.17, -Math.PI / 2, Math.PI / 2)
      ctx.stroke()

      // Chi (X), crossing the stem.
      ctx.beginPath()
      ctx.moveTo(s * 0.28, s * 0.82)
      ctx.lineTo(s * 0.72, s * 0.20)
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(s * 0.72, s * 0.82)
      ctx.lineTo(s * 0.28, s * 0.20)
      ctx.stroke()
    }
  }

  onForegroundChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()
  Component.onCompleted: canvas.requestPaint()
}
