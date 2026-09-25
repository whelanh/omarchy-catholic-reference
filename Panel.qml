import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Five-tab panel: Bible (Douay-Rheims) and Catechism fuzzy search, Catholic
// prayers, daily Mass readings, and the bundled Liturgy of the Hours. Search
// is delegated to bin/omarchy-catholic.
Panel {
  id: root
  moduleName: "io.github.whelanh.catholic-reference"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  property string currentTab: "bible"
  property string query: ""
  property string statusText: ""
  property int selectedIndex: 0
  property string runningKind: ""
  property string selectedPrayerId: ""

  property var pinnedResult: null
  property var commentaryParagraphs: []
  property bool commentaryLoading: false
  property bool pendingPin: false
  readonly property bool showingPinned: pinnedResult !== null

  // Window mode: the same content is reparented from the bar popup into a
  // resizable FloatingWindow, and the scroll areas grow to fill it.
  property bool windowed: false
  property Item popupHost: null
  readonly property bool showing: opened || windowed

  readonly property var barIdentity: hostWidget || root
  // Popup text must not inherit the wallpaper-adaptive transparent bar color.
  readonly property color panelForeground: (Color.popups.text !== undefined) ? Color.popups.text : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string readingsMeta: {
    if (!root.service) return ""
    var parts = []
    if (root.service.readings && root.service.readings.color) parts.push(root.service.readings.color)
    if (root.service.lectionary) parts.push(root.service.lectionary.label)
    return parts.join(" · ")
  }

  readonly property string scriptPath: {
    var path = String(Qt.resolvedUrl("bin/omarchy-catholic"))
    if (path.indexOf("file://") === 0) path = path.substring(7)
    return decodeURIComponent(path)
  }

  function focusContent() {
    if (!root.showingPinned && (root.currentTab === "bible" || root.currentTab === "catechism")) searchField.forceActiveFocus()
    else if (root.windowed) keyCatcher.forceActiveFocus()
    if (root.currentTab === "readings" && root.service) root.service.loadReadings()
  }

  function open() {
    if (root.windowed) return
    controller.show()
    Qt.callLater(root.focusContent)
  }

  function close() {
    if (root.windowed) root.closeWindow()
    else controller.hide()
  }

  function toggle() {
    if (root.showing) root.close()
    else root.open()
  }

  function openWindow() {
    if (!root.windowed) {
      root.popupHost = keyCatcher.parent
      root.windowed = true
      keyCatcher.parent = windowHost
    }
    if (root.opened) controller.hide()
    readerWindow.visible = true
    Qt.callLater(root.focusContent)
  }

  function closeWindow() {
    if (!root.windowed) return
    root.windowed = false
    readerWindow.visible = false
    if (root.popupHost) keyCatcher.parent = root.popupHost
  }

  // Height that fills the window from `top` (a y offset within the content
  // column) down to the bottom edge.
  function fillHeight(top) {
    return Math.max(Style.space(96), keyCatcher.height - top)
  }

  function setTab(tab) {
    if (root.currentTab === tab) return
    root.currentTab = tab
    root.query = ""
    root.unpinResult()
    resultModel.clear()
    root.selectedIndex = 0
    root.statusText = emptyStatus()
    if (tab === "prayers" && root.selectedPrayerId === "" && root.service && root.service.prayers) {
      var list = root.service.prayers.prayers || []
      if (list.length > 0) root.selectedPrayerId = list[0].id
    }
    if (tab === "readings" && root.service) root.service.loadReadings()
    if (tab === "bible" || tab === "catechism") Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function emptyStatus() {
    return root.currentTab === "bible"
      ? "Search by word, phrase, or reference."
      : "Search the Catechism by word or phrase."
  }

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (e) { return fallback }
  }

  function pinResult(reference, verse) {
    root.pinnedResult = { reference: reference, verse: verse }
    root.commentaryParagraphs = []
    root.commentaryLoading = true
    commentaryProc.command = [root.scriptPath, "commentary", reference]
    commentaryProc.running = true
    keyCatcher.forceActiveFocus()
  }

  function unpinResult() {
    root.pinnedResult = null
    root.commentaryParagraphs = []
    root.commentaryLoading = false
  }

  function scheduleSearch() {
    root.selectedIndex = 0
    searchTimer.restart()
  }

  function runSearch() {
    resultModel.clear()
    root.unpinResult()
    root.pendingPin = false
    if (root.currentTab !== "bible" && root.currentTab !== "catechism") return
    if (root.query.trim() === "") {
      root.statusText = emptyStatus()
      return
    }
    root.statusText = "Searching…"
    root.runningKind = root.currentTab
    searchProc.command = [
      root.scriptPath, "search",
      root.runningKind === "bible" ? "bible" : "catechism",
      root.query
    ]
    searchProc.running = true
  }

  function randomSearch() {
    if (root.currentTab !== "bible" && root.currentTab !== "catechism") return
    resultModel.clear()
    root.unpinResult()
    root.query = ""
    root.statusText = "Searching…"
    root.runningKind = root.currentTab
    root.pendingPin = root.currentTab === "bible"
    searchProc.command = [
      root.scriptPath, "random",
      root.runningKind === "bible" ? "bible" : "catechism"
    ]
    searchProc.running = true
  }

  function parseSearchOutput(raw) {
    if (root.runningKind !== root.currentTab) return
    var lines = String(raw || "").split("\n")
    var found = 0
    var books = 0
    var chapters = 0
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts.length >= 2 && parts[0] === "STATUS") {
        root.statusText = parts.slice(1).join(" ")
      } else if (parts.length >= 3 && parts[0] === "RESULT") {
        resultModel.append({ reference: parts[1], verse: parts.slice(2).join(" "), fill: "" })
        found++
      } else if (parts.length >= 4 && parts[0] === "NAV") {
        // A book or chapter: opening it searches `fill` instead of copying.
        resultModel.append({ reference: parts[1], verse: parts[2], fill: parts[3] })
        if (/ $/.test(parts[3])) books++
        else chapters++
      }
    }
    var summary = []
    if (books > 0) summary.push(books + " book" + (books === 1 ? "" : "s"))
    if (chapters > 0) summary.push(chapters + " chapter" + (chapters === 1 ? "" : "s"))
    if (found > 0) summary.push(found + " result" + (found === 1 ? "" : "s"))
    if (summary.length > 0) root.statusText = summary.join(" · ")
    root.selectedIndex = 0
    if (root.pendingPin) {
      root.pendingPin = false
      if (found >= 1) {
        var row = resultModel.get(0)
        root.pinResult(row.reference, row.verse)
      }
    }
  }

  function moveSelection(delta) {
    if (resultModel.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + resultModel.count) % resultModel.count
    var item = resultRepeater.itemAt(root.selectedIndex)
    if (!item) return
    var top = resultColumn.y + item.y
    var bottom = top + item.height
    if (top < resultList.contentY) resultList.contentY = top
    else if (bottom > resultList.contentY + resultList.height) resultList.contentY = bottom - resultList.height
  }

  function selectedFill() {
    if (root.selectedIndex < 0 || root.selectedIndex >= resultModel.count) return ""
    return resultModel.get(root.selectedIndex).fill
  }

  function openNav(fill) {
    searchField.text = fill
    searchField.cursorPosition = fill.length
    searchField.forceActiveFocus()
    resultList.contentY = 0
  }

  function activateSelected() {
    if (resultModel.count > 0) copyResult(root.selectedIndex)
  }

  function copyResult(index) {
    if (index < 0 || index >= resultModel.count) return
    var row = resultModel.get(index)
    if (row.fill !== "") {
      root.openNav(row.fill)
      return
    }
    var text = row.reference + " — " + row.verse
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    if (root.currentTab === "bible") {
      root.pinResult(row.reference, row.verse)
    } else {
      root.close()
    }
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function hourActive(id) {
    if (!root.service) return false
    if (root.service.selectedHourId !== "") return root.service.selectedHourId === id
    if (root.service.featured) return root.service.featured.id === id
    return false
  }

  function selectedPrayer() {
    if (!root.service || !root.service.prayers) return null
    var list = root.service.prayers.prayers || []
    for (var i = 0; i < list.length; i++) if (list[i].id === root.selectedPrayerId) return list[i]
    return list.length > 0 ? list[0] : null
  }

  ListModel { id: resultModel }

  Timer {
    id: searchTimer
    interval: 160
    repeat: false
    onTriggered: root.runSearch()
  }

  Process {
    id: searchProc
    running: false
    stdout: StdioCollector {
      id: searchOutput
      waitForEnd: true
    }
    onExited: function() {
      if (root.showing) root.parseSearchOutput(searchOutput.text)
    }
  }

  Process {
    id: commentaryProc
    running: false
    stdout: StdioCollector {
      id: commentaryOutput
      waitForEnd: true
    }
    onExited: function() {
      root.commentaryLoading = false
      var data = root.parseJson(commentaryOutput.text, null)
      root.commentaryParagraphs = data && Array.isArray(data.p) ? data.p : []
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(520))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onCloseRequested: {
        if (root.showingPinned) {
          root.unpinResult()
          Qt.callLater(function() { searchField.forceActiveFocus() })
        } else {
          root.close()
        }
      }
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveSelection(dy) }
      onActivateRequested: root.activateSelected()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.md

        Item {
          id: header
          width: parent.width
          height: Style.space(46)

          BorderSurface {
            id: iconBadge
            width: Style.space(42)
            height: Style.space(42)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: Style.hoverFillFor(root.panelForeground, Color.accent)
            borderSpec: Border.flat(Color.accent, 1)
            radius: Style.cornerRadius

            ChiRho {
              anchors.centerIn: parent
              foreground: root.panelForeground
              size: Style.space(30)
            }
          }

          Column {
            anchors.left: iconBadge.right
            anchors.leftMargin: Style.spacing.sm
            anchors.right: headerControls.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Text {
              id: headerTitle
              text: "Catholic Reference"
              textFormat: Text.PlainText
              color: root.panelForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              text: "Douay-Rheims Bible · Catechism · Prayers · Readings · Hours"
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              color: root.panelForeground
              opacity: 0.62
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            id: headerControls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            Button {
              id: windowButton
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.windowed
              text: "Pop out"
              tooltipText: "Open in a resizable window"
              bordered: true
              foreground: root.panelForeground
              fontSize: Style.font.caption
              onClicked: root.openWindow()
            }

            Text {
              id: closeHint
              anchors.verticalCenter: parent.verticalCenter
              text: "ESC"
              textFormat: Text.PlainText
              color: root.panelForeground
              opacity: 0.62
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }
          }
        }

        Row {
          id: tabRow
          width: parent.width
          spacing: Style.spacing.xs

          Button {
            width: (parent.width - parent.spacing * 4) / 5
            text: "Bible"
            selected: root.currentTab === "bible"
            bordered: true
            foreground: root.panelForeground
            onClicked: root.setTab("bible")
          }
          Button {
            width: (parent.width - parent.spacing * 4) / 5
            text: "Catechism"
            selected: root.currentTab === "catechism"
            bordered: true
            foreground: root.panelForeground
            onClicked: root.setTab("catechism")
          }
          Button {
            width: (parent.width - parent.spacing * 4) / 5
            text: "Prayers"
            selected: root.currentTab === "prayers"
            bordered: true
            foreground: root.panelForeground
            onClicked: root.setTab("prayers")
          }
          Button {
            width: (parent.width - parent.spacing * 4) / 5
            text: "Readings"
            selected: root.currentTab === "readings"
            bordered: true
            foreground: root.panelForeground
            onClicked: root.setTab("readings")
          }
          Button {
            width: (parent.width - parent.spacing * 4) / 5
            text: "Hours"
            selected: root.currentTab === "hours"
            bordered: true
            foreground: root.panelForeground
            onClicked: root.setTab("hours")
          }
        }

        Column {
          id: searchArea
          width: parent.width
          visible: root.currentTab === "bible" || root.currentTab === "catechism"
          spacing: Style.spacing.md

          TextField {
            id: searchField
            width: parent.width
            visible: !root.showingPinned
            placeholderText: root.currentTab === "bible" ? "Search the Bible…" : "Search the Catechism…"
            foreground: root.panelForeground
            accent: Color.accent
            rightPadding: Style.space(54)
            text: root.query
            onTextChanged: {
              if (root.query !== text) root.query = text
              root.scheduleSearch()
            }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (resultModel.count === 0) return
              if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activateSelected()
                event.accepted = true
              }
            }

            onAccepted: {
              searchField.focus = false
              keyCatcher.forceActiveFocus()
            }
            Keys.onEscapePressed: {
              searchField.focus = false
              keyCatcher.forceActiveFocus()
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              text: "ENTER"
              textFormat: Text.PlainText
              color: root.panelForeground
              opacity: 0.48
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 0.8
            }
          }

          Row {
            id: quickSearches
            width: parent.width
            visible: !root.showingPinned && root.query.trim() === ""
            spacing: Style.spacing.xs

            Repeater {
              model: root.currentTab === "bible"
                ? ["random", "love", "faith", "peace", "wisdom"]
                : ["random", "prayer", "sacrament", "charity", "grace"]

              delegate: Rectangle {
                required property string modelData
                width: chipLabel.implicitWidth + Style.space(20)
                height: Style.space(28)
                radius: height / 2
                color: chipMouse.containsMouse
                  ? Style.hoverFillFor(root.panelForeground, Color.accent)
                  : "transparent"
                border.width: 1
                border.color: Color.popups.border

                Text {
                  id: chipLabel
                  anchors.centerIn: parent
                  text: parent.modelData
                  textFormat: Text.PlainText
                  color: root.panelForeground
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  id: chipMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (parent.modelData === "random") {
                      root.randomSearch()
                    } else {
                      searchField.text = parent.modelData
                      searchField.forceActiveFocus()
                    }
                  }
                }
              }
            }
          }

          Text {
            id: introText
            width: parent.width
            visible: !root.showingPinned && root.query.trim() === "" && resultModel.count === 0
            text: root.currentTab === "bible"
              ? "Try a theme, phrase, book, or verse reference. Click a result to copy it."
              : "Try a topic or phrase. Click a paragraph to copy it."
            textFormat: Text.PlainText
            color: root.panelForeground
            opacity: 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            id: statusRow
            width: parent.width
            visible: !root.showingPinned && (resultModel.count > 0 || root.query.trim() !== "")
            spacing: Style.spacing.sm

            Text {
              id: statusLabel
              width: Math.min(Style.space(260), implicitWidth)
              text: root.statusText
              textFormat: Text.PlainText
              color: root.panelForeground
              opacity: 0.64
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Item {
              width: Math.max(0, parent.width - statusLabel.width - keyboardHint.implicitWidth - Style.spacing.sm)
              height: 1
            }

            Text {
              id: keyboardHint
              text: resultModel.count > 0
                ? "↑ ↓  navigate · ENTER  " + (root.selectedIndex >= 0 && root.selectedIndex < resultModel.count && resultModel.get(root.selectedIndex).fill !== "" ? "open" : "copy")
                : ""
              textFormat: Text.PlainText
              color: root.panelForeground
              opacity: 0.46
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Flickable {
            id: resultList
            width: parent.width
            visible: !root.showingPinned && (resultModel.count > 0 || root.query.trim() !== "")
            height: root.windowed ? root.fillHeight(searchArea.y + y) : Math.min(Style.space(320), Math.max(Style.space(96), resultStack.implicitHeight))
            clip: true
            contentWidth: width
            contentHeight: resultStack.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: resultStack
              width: resultList.width
              spacing: Style.spacing.xs

              Item {
                id: emptyState
                visible: resultModel.count === 0
                width: resultStack.width
                height: Style.space(96)

                Text {
                  anchors.centerIn: parent
                  text: root.statusText.indexOf("Searching") === 0
                    ? (root.currentTab === "bible" ? "Searching the Bible…" : "Searching the Catechism…")
                    : "No matches"
                  textFormat: Text.PlainText
                  color: root.panelForeground
                  opacity: 0.62
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Column {
                id: resultColumn
                width: resultStack.width
                spacing: Style.spacing.xs
                visible: resultModel.count > 0

                Repeater {
                  id: resultRepeater
                  model: resultModel
                  delegate: Item {
                    required property int index
                    required property string reference
                    required property string verse
                    required property string fill

                    width: resultColumn.width
                    height: fill !== ""
                      ? verseText.implicitHeight + Style.space(40)
                      : Math.max(Style.space(82), verseText.implicitHeight + Style.space(40))

                    BorderSurface {
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: root.selectedIndex === index
                        ? Style.hoverFillFor(root.panelForeground, Color.accent)
                        : "transparent"
                      borderSpec: root.selectedIndex === index
                        ? Border.controlSpec("hover-cursor", root.panelForeground, Color.accent)
                        : Border.flat(Color.popups.border, 1)
                    }

                    Column {
                      anchors.fill: parent
                      anchors.margins: Style.spacing.sm
                      spacing: Style.spacing.xs

                      Row {
                        width: parent.width

                        Text {
                          id: referenceLabel
                          text: reference
                          textFormat: Text.PlainText
                          color: root.panelForeground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }

                        Item {
                          width: Math.max(0, parent.width - referenceLabel.implicitWidth - copyHint.implicitWidth - Style.spacing.sm)
                          height: 1
                        }

                        Text {
                          id: copyHint
                          text: fill !== "" ? "OPEN" : "COPY"
                          textFormat: Text.PlainText
                          color: root.panelForeground
                          opacity: 0.46
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.letterSpacing: 0.8
                        }
                      }

                      Text {
                        id: verseText
                        width: parent.width
                        text: verse
                        textFormat: Text.PlainText
                        color: root.panelForeground
                        opacity: fill !== "" ? 0.72 : 1
                        font.family: root.fontFamily
                        font.pixelSize: fill !== "" ? Style.font.bodySmall : Style.font.body
                        wrapMode: Text.WordWrap
                        maximumLineCount: fill !== "" ? 1 : 1000
                        elide: fill !== "" ? Text.ElideRight : Text.ElideNone
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.selectedIndex = index
                      onClicked: root.copyResult(index)
                    }
                  }
                }
              }
            }
          }
        Column {
          id: pinnedView
          width: parent.width
          visible: root.showingPinned
          spacing: Style.spacing.md

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Button {
              id: backButton
              text: "Back"
              selected: false
              bordered: true
              foreground: root.panelForeground
              onClicked: {
                root.unpinResult()
                searchField.forceActiveFocus()
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.pinnedResult ? root.pinnedResult.reference : ""
              textFormat: Text.PlainText
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          Text {
            width: parent.width
            text: root.pinnedResult ? root.pinnedResult.verse : ""
            textFormat: Text.PlainText
            color: root.panelForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "COMMENTARY"
            textFormat: Text.PlainText
            color: root.panelForeground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            visible: root.commentaryLoading
            text: "Loading commentary…"
            textFormat: Text.PlainText
            color: root.panelForeground
            opacity: 0.62
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Flickable {
            width: parent.width
            visible: !root.commentaryLoading
            height: root.windowed ? root.fillHeight(pinnedView.y + y) : Math.min(Style.space(400), commentaryColumn.implicitHeight)
            clip: true
            contentWidth: width
            contentHeight: commentaryColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: commentaryColumn
              width: parent.width
              spacing: Style.spacing.sm

              Text {
                width: parent.width
                visible: root.commentaryParagraphs.length === 0
                text: "No commentary available for this verse."
                textFormat: Text.PlainText
                color: root.panelForeground
                opacity: 0.62
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Repeater {
                model: root.commentaryParagraphs
                delegate: Column {
                  required property var modelData
                  width: commentaryColumn.width
                  spacing: Style.spacing.xs

                  Text {
                    width: parent.width
                    visible: modelData[0] !== ""
                    text: modelData[0]
                    textFormat: Text.PlainText
                    color: root.panelForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    width: parent.width
                    visible: modelData[1] !== ""
                    text: modelData[1]
                    textFormat: Text.PlainText
                    color: root.panelForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }
          }
        }
        }

        Column {
          id: prayersArea
          width: parent.width
          visible: root.currentTab === "prayers"
          spacing: Style.spacing.md

          Grid {
            id: prayersGrid
            width: parent.width
            columns: 2
            spacing: Style.spacing.xs

            Repeater {
              model: root.service && root.service.prayers ? root.service.prayers.prayers : []
              delegate: Button {
                required property var modelData
                width: (prayersGrid.width - prayersGrid.spacing) / 2
                text: modelData.name
                selected: root.selectedPrayerId === modelData.id
                bordered: true
                foreground: root.panelForeground
                onClicked: root.selectedPrayerId = modelData.id
              }
            }
          }

          Flickable {
            id: prayerDetail
            width: parent.width
            height: root.windowed ? root.fillHeight(prayersArea.y + y) : Math.min(Style.space(340), prayerColumn.implicitHeight)
            clip: true
            contentWidth: width
            contentHeight: prayerColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: prayerColumn
              width: prayerDetail.width
              spacing: Style.spacing.sm

              Text {
                width: parent.width
                text: root.selectedPrayer() ? root.selectedPrayer().name : ""
                textFormat: Text.PlainText
                color: root.panelForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                visible: root.selectedPrayer() && root.selectedPrayer().latin_name !== ""
                text: root.selectedPrayer() ? root.selectedPrayer().latin_name : ""
                textFormat: Text.PlainText
                color: root.panelForeground
                opacity: 0.62
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                text: "ENGLISH"
                textFormat: Text.PlainText
                color: root.panelForeground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                width: parent.width
                text: root.selectedPrayer() ? root.selectedPrayer().english : ""
                textFormat: Text.PlainText
                color: root.panelForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                visible: root.selectedPrayer() && root.selectedPrayer().latin !== ""
                text: "LATIN"
                textFormat: Text.PlainText
                color: root.panelForeground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                width: parent.width
                visible: root.selectedPrayer() && root.selectedPrayer().latin !== ""
                text: root.selectedPrayer() ? root.selectedPrayer().latin : ""
                textFormat: Text.PlainText
                color: root.panelForeground
                opacity: 0.85
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }
          }
        }

        Column {
          id: readingsArea
          width: parent.width
          visible: root.currentTab === "readings"
          spacing: Style.spacing.md

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Column {
              width: parent.width - refreshButton.width - parent.spacing
              spacing: Style.spacing.xs

              Text {
                width: parent.width
                text: root.service && root.service.readings ? root.service.readings.title : ""
                textFormat: Text.PlainText
                color: root.panelForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                text: root.readingsMeta
                textFormat: Text.PlainText
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Button {
              id: refreshButton
              text: "Refresh"
              selected: false
              bordered: true
              foreground: root.panelForeground
              tooltipText: "Refresh today's readings"
              onClicked: { if (root.service) root.service.loadReadings(true) }
            }
          }

          Text {
            width: parent.width
            visible: root.service && root.service.readingsLoading && !root.service.readings
            text: "Loading today's readings…"
            textFormat: Text.PlainText
            color: root.panelForeground
            opacity: 0.62
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: root.service && root.service.readingsError !== "" && !root.service.readings
            text: "Offline — couldn't fetch today's readings.\n" + (root.service ? root.service.readingsError : "")
            textFormat: Text.PlainText
            color: root.panelForeground
            opacity: 0.62
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Flickable {
            id: readingsList
            width: parent.width
            visible: root.service && root.service.readings
            height: root.windowed ? root.fillHeight(readingsArea.y + y) : Math.min(Style.space(400), readingsColumn.implicitHeight)
            clip: true
            contentWidth: width
            contentHeight: readingsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: readingsColumn
              width: readingsList.width
              spacing: Style.spacing.md

              Repeater {
                model: root.service && root.service.readings ? root.service.readings.readings : []
                delegate: Column {
                  required property var modelData
                  width: readingsColumn.width
                  spacing: Style.space(4)

                  readonly property var bodyLines: {
                    var ls = modelData.lines
                    if (ls && ls.length) return ls
                    var out = []
                    var raw = String(modelData.text || "").split("\n")
                    for (var i = 0; i < raw.length; i++) if (raw[i] !== "") out.push({ t: raw[i], r: false })
                    return out
                  }

                  Rectangle {
                    visible: modelData.optionalStart === true
                    width: parent.width
                    height: 1
                    color: Color.popups.border
                  }
                  Text {
                    visible: modelData.optionalStart === true
                    width: parent.width
                    text: "OPTIONAL READINGS"
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    text: modelData.label ? String(modelData.label).toUpperCase() : ""
                    textFormat: Text.PlainText
                    color: root.panelForeground
                    opacity: 0.62
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Text {
                    width: parent.width
                    text: modelData.reference || ""
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    width: parent.width
                    visible: modelData.heading !== ""
                    text: modelData.heading || ""
                    textFormat: Text.PlainText
                    color: root.panelForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.italic: true
                    wrapMode: Text.WordWrap
                  }

                  Repeater {
                    model: bodyLines
                    delegate: Text {
                      required property var modelData
                      width: parent.width
                      text: modelData.t || ""
                      textFormat: Text.PlainText
                      color: root.panelForeground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: modelData.r === true
                      font.italic: modelData.r === true
                      wrapMode: Text.WordWrap
                    }
                  }
                }
              }
            }
          }
        }

        Column {
          id: hoursArea
          width: parent.width
          visible: root.currentTab === "hours"
          spacing: Style.spacing.md

          Text {
            width: parent.width
            text: root.service && root.service.office ? root.service.office.heading : ""
            textFormat: Text.PlainText
            color: root.panelForeground
            opacity: 0.62
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.service && root.service.office ? root.service.office.hourName : ""
            textFormat: Text.PlainText
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Row {
            id: hoursRow
            width: parent.width
            spacing: Style.spacing.xs

            Repeater {
              model: Model.HOURS
              delegate: Button {
                required property var modelData
                width: (hoursRow.width - hoursRow.spacing * 3) / 4
                text: modelData.shortName
                selected: root.hourActive(modelData.id)
                bordered: true
                foreground: root.panelForeground
                onClicked: {
                  if (root.service) root.service.selectedHourId = modelData.id
                }
              }
            }
          }

          Flickable {
            id: officeView
            width: parent.width
            height: root.windowed ? root.fillHeight(hoursArea.y + y) : Math.min(Style.space(380), officeColumn.implicitHeight)
            clip: true
            contentWidth: width
            contentHeight: officeColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: officeColumn
              width: officeView.width
              spacing: Style.spacing.md

              Repeater {
                model: root.service && root.service.office ? root.service.office.sections : []
                delegate: Column {
                  required property var modelData
                  width: officeColumn.width
                  spacing: Style.space(4)

                  Text {
                    width: parent.width
                    text: modelData.label ? String(modelData.label).toUpperCase() : ""
                    textFormat: Text.PlainText
                    color: root.panelForeground
                    opacity: 0.62
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Text {
                    width: parent.width
                    text: modelData.body || ""
                    textFormat: Text.PlainText
                    color: root.panelForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  FloatingWindow {
    id: readerWindow
    visible: false
    title: "Catholic Reference"
    color: Color.popups.background
    implicitWidth: Style.space(760)
    implicitHeight: Style.space(900)
    minimumSize: Qt.size(Style.space(420), Style.space(420))

    // Closed by the compositor (e.g. SUPER+W): move the content back.
    onVisibleChanged: if (!visible) root.closeWindow()

    Item {
      id: windowHost
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
    }
  }
}
