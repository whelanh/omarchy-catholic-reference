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
    root.closeReader()
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
    root.closeReader()
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
    root.closeReader()
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
      // "Matthew " (a book) searches for its chapters; "Matthew 4" reads it.
      var chapter = row.fill.match(/^(.+) (\d+)$/)
      if (chapter) root.openChapter(chapter[1], parseInt(chapter[2], 10))
      else root.openNav(row.fill)
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

  // --- Browse outline and reader ------------------------------------------

  // What the reader shows: {kind: "bible", book, chapter} or
  // {kind: "catechism", title, first, last}. Null when not reading.
  property var reading: null
  property var readingData: null
  property string readerNote: ""
  // Outline groups the user has opened, keyed by path ("0.2", "c1.0").
  property var expanded: ({})
  readonly property bool showingReader: reading !== null && !showingPinned
  readonly property bool showingBrowse: !showingPinned && reading === null && query.trim() === ""
    && resultModel.count === 0 && (currentTab === "bible" || currentTab === "catechism")

  function openChapter(book, chapter) {
    root.reading = { kind: "bible", book: book, chapter: chapter }
    root.loadReading([root.scriptPath, "chapter", book, String(chapter)])
  }

  function openCatechism(title, first, last) {
    root.reading = { kind: "catechism", title: title, first: first, last: last }
    root.loadReading([root.scriptPath, "ccc", String(first), String(last)])
  }

  function loadReading(command) {
    root.readingData = null
    root.readerNote = ""
    readerList.contentY = 0
    readerProc.command = command
    readerProc.running = true
    keyCatcher.forceActiveFocus()
  }

  function closeReader() {
    root.readingData = null
    root.reading = null
  }

  function toggleExpanded(key) {
    var next = {}
    for (var k in root.expanded) next[k] = root.expanded[k]
    next[key] = !next[key]
    root.expanded = next
  }

  // Catechism outline leaves in reading order, for previous/next.
  function catechismLeaves() {
    var out = []
    function walk(nodes) {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].c) walk(nodes[i].c)
        else out.push(nodes[i])
      }
    }
    walk(root.service && root.service.outline ? root.service.outline.catechism : [])
    return out
  }

  function stepReading(delta) {
    var r = root.reading
    if (!r) return
    if (r.kind === "bible") {
      var total = root.readingData ? root.readingData.chapters : 0
      var next = r.chapter + delta
      if (next >= 1 && next <= total) root.openChapter(r.book, next)
      return
    }
    var leaves = root.catechismLeaves()
    for (var i = 0; i < leaves.length; i++) {
      if (leaves[i].a === r.first) {
        var leaf = leaves[i + delta]
        if (leaf) root.openCatechism(leaf.t, leaf.a, leaf.b)
        return
      }
    }
  }

  function canStep(delta) {
    var r = root.reading
    if (!r) return false
    if (r.kind === "bible") {
      var next = r.chapter + delta
      return next >= 1 && root.readingData !== null && next <= root.readingData.chapters
    }
    if (delta < 0) return r.first > 1
    return r.last < 2865
  }

  function readerTitle() {
    var r = root.reading
    if (!r) return ""
    if (r.kind === "bible") return r.book + " " + r.chapter
    return r.title
  }

  function readerRange() {
    var r = root.reading
    if (!r || r.kind !== "catechism") return ""
    return r.first === r.last ? "CCC " + r.first : "CCC " + r.first + "–" + r.last
  }

  function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  // Rich text for the reader. Verse and paragraph numbers are links: a verse
  // opens its card with commentary, a paragraph number copies the paragraph.
  function readerHtml() {
    var d = root.readingData
    if (!d || !root.reading) return ""
    var accent = String(Color.accent)
    var parts = []
    if (root.reading.kind === "bible") {
      for (var i = 0; i < d.verses.length; i++) {
        var v = d.verses[i]
        parts.push("<a href=\"v:" + v[0] + "\" style=\"color:" + accent + "; text-decoration:none\"><b>" + v[0] + "</b></a>&nbsp;" + root.escapeHtml(v[1]))
      }
      return d.poetic ? parts.join("<br>") : parts.join(" &nbsp;")
    }
    var headings = {}
    for (var h = 0; h < d.headings.length; h++) headings[d.headings[h][0]] = d.headings[h][1]
    for (var j = 0; j < d.paragraphs.length; j++) {
      var p = d.paragraphs[j]
      if (headings[p[0]]) parts.push("<p><b>" + root.escapeHtml(headings[p[0]]) + "</b></p>")
      var number = "<a href=\"p:" + p[0] + "\" style=\"color:" + accent + "; text-decoration:none\"><b>" + p[0] + "</b></a>&nbsp; "
      parts.push(root.catechismHtml(p[1], number, accent))
    }
    return parts.join("")
  }

  // The Catechism text carries light markdown: blank lines between blocks,
  // "> " quotations, *italics*, and cross-references like "(843, 2095-2109)",
  // which become links to those paragraphs.
  function catechismHtml(text, number, accent) {
    var blocks = String(text).trim().split(/\n\s*\n+/)
    var out = []
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i].trim()
      var quote = /^>/.test(block)
      block = root.escapeHtml(block.replace(/^>\s?/gm, "").replace(/\*\*/g, ""))
        .replace(/\*([^*\n]+)\*/g, "<i>$1</i>")
        .replace(/\((\d+(?:-\d+)?(?:,\s*\d+(?:-\d+)?)*)\)/g, function(all, refs) {
          return "(" + refs.split(/,\s*/).map(function(r) {
            return "<a href=\"r:" + r + "\" style=\"color:" + accent + "; text-decoration:none\">" + r + "</a>"
          }).join(", ") + ")"
        })
        .replace(/\n/g, "<br>")
      if (i === 0) block = number + block
      out.push(quote ? "<blockquote><i>" + block + "</i></blockquote>" : "<p>" + block + "</p>")
    }
    return out.join("")
  }

  function copyText(text) {
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function readerLink(link) {
    var d = root.readingData
    if (!d) return
    if (link.indexOf("r:") === 0) {
      var range = link.substring(2).split("-")
      var first = parseInt(range[0], 10)
      var last = parseInt(range[1] || range[0], 10)
      root.openCatechism(first === last ? "CCC " + first : "CCC " + first + "–" + last, first, last)
      return
    }
    var n = parseInt(link.substring(2), 10)
    var list = link.indexOf("v:") === 0 ? d.verses : d.paragraphs
    for (var i = 0; i < list.length; i++) {
      if (list[i][0] !== n) continue
      if (link.indexOf("v:") === 0) {
        var reference = d.book + " " + d.chapter + ":" + n
        root.copyText(reference + " — " + list[i][1])
        root.pinResult(reference, list[i][1])
      } else {
        root.copyText("CCC " + n + " — " + String(list[i][1]).trim())
        root.readerNote = "Copied CCC " + n
      }
      return
    }
  }

  // Visible outline rows for the current tab, flattened for a Repeater:
  //   {type: "label", text}
  //   {type: "group", key, text, detail, open, depth}
  //   {type: "books", books: [{name, chapters}]}
  //   {type: "leaf", text, detail, first, last, depth}
  function browseRows() {
    var outline = root.service && root.service.outline ? root.service.outline : null
    var rows = []
    if (!outline) return rows
    if (root.currentTab === "bible") {
      var testaments = outline.bible || []
      for (var t = 0; t < testaments.length; t++) {
        rows.push({ type: "label", text: testaments[t].name })
        var divisions = testaments[t].divisions
        for (var d = 0; d < divisions.length; d++) {
          var key = t + "." + d
          var count = divisions[d].books.length
          rows.push({ type: "group", key: key, text: divisions[d].name,
            detail: count + (count === 1 ? " book" : " books"), open: !!root.expanded[key], depth: 0 })
          if (root.expanded[key]) rows.push({ type: "books", books: divisions[d].books })
        }
      }
      return rows
    }
    function walk(nodes, prefix, depth) {
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i]
        var range = n.a === n.b ? "¶ " + n.a : "¶ " + n.a + "–" + n.b
        if (n.c) {
          var k = prefix + i
          rows.push({ type: "group", key: k, text: n.t, detail: range, open: !!root.expanded[k], depth: depth })
          if (root.expanded[k]) walk(n.c, k + ".", depth + 1)
        } else {
          rows.push({ type: "leaf", text: n.t, detail: range, first: n.a, last: n.b, depth: depth })
        }
      }
    }
    walk(outline.catechism || [], "c", 0)
    return rows
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
    id: readerProc
    running: false
    stdout: StdioCollector {
      id: readerOutput
      waitForEnd: true
    }
    onExited: function() {
      if (root.reading === null) return
      var data = root.parseJson(readerOutput.text, null)
      root.readingData = data
      if (!data || (data.verses && data.verses.length === 0) || (data.paragraphs && data.paragraphs.length === 0)) {
        root.readerNote = "Nothing found for " + root.readerTitle()
      }
    }
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
          if (root.reading === null) Qt.callLater(function() { searchField.forceActiveFocus() })
        } else if (root.reading !== null) {
          root.closeReader()
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
            visible: !root.showingPinned && !root.showingReader && root.query.trim() === ""
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

          // With nothing typed, the tab opens on its outline: Old and New
          // Testament divisions, or the Catechism's Parts down to Articles.
          Flickable {
            id: browseList
            width: parent.width
            visible: root.showingBrowse
            height: root.windowed ? root.fillHeight(searchArea.y + y) : Math.min(Style.space(420), browseColumn.implicitHeight)
            clip: true
            contentWidth: width
            contentHeight: browseColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: browseColumn
              width: browseList.width
              spacing: Style.spacing.xs

              Repeater {
                model: root.showingBrowse ? root.browseRows() : []

                delegate: Item {
                  id: browseRow
                  required property var modelData
                  readonly property int indent: (modelData.depth || 0) * Style.space(14)

                  width: browseColumn.width
                  height: modelData.type === "label"
                    ? browseLabel.implicitHeight + Style.spacing.xs
                    : modelData.type === "books"
                      ? bookFlow.implicitHeight + Style.spacing.xs
                      : Math.max(Style.space(30), rowTitle.implicitHeight + Style.space(12))

                  Text {
                    id: browseLabel
                    visible: browseRow.modelData.type === "label"
                    anchors.bottom: parent.bottom
                    text: browseRow.modelData.type === "label" ? browseRow.modelData.text.toUpperCase() : ""
                    textFormat: Text.PlainText
                    color: root.panelForeground
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1.2
                  }

                  Flow {
                    id: bookFlow
                    visible: browseRow.modelData.type === "books"
                    x: Style.space(14)
                    width: parent.width - x
                    spacing: Style.spacing.xs

                    Repeater {
                      model: browseRow.modelData.type === "books" ? browseRow.modelData.books : []

                      delegate: Rectangle {
                        required property var modelData
                        width: bookLabel.implicitWidth + Style.space(20)
                        height: Style.space(28)
                        radius: height / 2
                        color: bookMouse.containsMouse
                          ? Style.hoverFillFor(root.panelForeground, Color.accent)
                          : "transparent"
                        border.width: 1
                        border.color: bookMouse.containsMouse ? Color.accent : Color.popups.border

                        Text {
                          id: bookLabel
                          anchors.centerIn: parent
                          text: parent.modelData.name + "  " + parent.modelData.chapters
                          textFormat: Text.PlainText
                          color: root.panelForeground
                          opacity: 0.85
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                        }

                        MouseArea {
                          id: bookMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.openNav(parent.modelData.name + " ")
                        }
                      }
                    }
                  }

                  BorderSurface {
                    visible: browseRow.modelData.type === "group" || browseRow.modelData.type === "leaf"
                    x: browseRow.indent
                    width: parent.width - x
                    height: parent.height
                    radius: Style.cornerRadius
                    color: rowMouse.containsMouse ? Style.hoverFillFor(root.panelForeground, Color.accent) : "transparent"
                    borderSpec: rowMouse.containsMouse
                      ? Border.controlSpec("hover-cursor", root.panelForeground, Color.accent)
                      : Border.flat(Color.popups.border, 1)

                    Text {
                      id: rowTitle
                      anchors.left: parent.left
                      anchors.leftMargin: Style.spacing.sm
                      anchors.right: rowDetail.left
                      anchors.rightMargin: Style.spacing.sm
                      anchors.verticalCenter: parent.verticalCenter
                      text: browseRow.modelData.type === "group"
                        ? (browseRow.modelData.open ? "▾  " : "▸  ") + browseRow.modelData.text
                        : browseRow.modelData.text || ""
                      textFormat: Text.PlainText
                      color: root.panelForeground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: browseRow.modelData.type === "group" && (browseRow.modelData.depth || 0) === 0
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      id: rowDetail
                      anchors.right: parent.right
                      anchors.rightMargin: Style.spacing.sm
                      anchors.verticalCenter: parent.verticalCenter
                      text: browseRow.modelData.detail || ""
                      textFormat: Text.PlainText
                      color: root.panelForeground
                      opacity: 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      id: rowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        var row = browseRow.modelData
                        if (row.type === "group") root.toggleExpanded(row.key)
                        else root.openCatechism(row.text, row.first, row.last)
                      }
                    }
                  }
                }
              }
            }
          }

          Row {
            id: statusRow
            width: parent.width
            visible: !root.showingPinned && !root.showingReader && (resultModel.count > 0 || root.query.trim() !== "")
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
            visible: !root.showingPinned && !root.showingReader && (resultModel.count > 0 || root.query.trim() !== "")
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
        // Reading a whole chapter or Catechism section as running text.
        Column {
          id: readerView
          width: parent.width
          visible: root.showingReader
          spacing: Style.spacing.md

          Item {
            width: parent.width
            height: readerBack.implicitHeight

            Button {
              id: readerBack
              text: "Back"
              bordered: true
              foreground: root.panelForeground
              onClicked: {
                root.closeReader()
                searchField.forceActiveFocus()
              }
            }

            Column {
              anchors.left: readerBack.right
              anchors.leftMargin: Style.spacing.sm
              anchors.right: readerSteps.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter

              Text {
                width: parent.width
                text: root.readerTitle()
                textFormat: Text.PlainText
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: root.readerNote !== "" ? root.readerNote : root.readerRange()
                textFormat: Text.PlainText
                color: root.panelForeground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Row {
              id: readerSteps
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              Button {
                text: "‹"
                tooltipText: root.reading && root.reading.kind === "bible" ? "Previous chapter" : "Previous section"
                bordered: true
                enabled: root.canStep(-1)
                opacity: enabled ? 1 : 0.35
                foreground: root.panelForeground
                onClicked: root.stepReading(-1)
              }

              Button {
                text: "›"
                tooltipText: root.reading && root.reading.kind === "bible" ? "Next chapter" : "Next section"
                bordered: true
                enabled: root.canStep(1)
                opacity: enabled ? 1 : 0.35
                foreground: root.panelForeground
                onClicked: root.stepReading(1)
              }
            }
          }

          Text {
            width: parent.width
            visible: root.readingData === null && root.readerNote === ""
            text: "Loading…"
            textFormat: Text.PlainText
            color: root.panelForeground
            opacity: 0.62
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Flickable {
            id: readerList
            width: parent.width
            visible: root.readingData !== null
            height: root.windowed ? root.fillHeight(searchArea.y + readerView.y + y) : Math.min(Style.space(420), readerText.implicitHeight)
            clip: true
            contentWidth: width
            contentHeight: readerText.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Text {
              id: readerText
              width: readerList.width
              text: root.readerHtml()
              textFormat: Text.RichText
              color: root.panelForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              lineHeight: 1.25
              wrapMode: Text.WordWrap
              onLinkActivated: function(link) { root.readerLink(link) }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: readerText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
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
            height: root.windowed ? root.fillHeight(searchArea.y + pinnedView.y + y) : Math.min(Style.space(400), commentaryColumn.implicitHeight)
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
