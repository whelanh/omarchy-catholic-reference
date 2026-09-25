import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Persistent state for the Catholic Reference widget. Loads the bundled
// office content (data/office.json) and prayers (data/prayers.json), derives
// the current hour's office, and fetches today's Mass readings from
// universalis.com via the Node helper. The Bible and Catechism corpora are
// read directly by the Node search helper, so they never need to be parsed
// by the QML runtime.
Item {
  id: root
  property var settings: ({})
  property string selectedHourId: ""

  function fileUrlToPath(url) {
    var s = String(url || "")
    if (s.indexOf("file://") === 0) s = s.substring(7)
    try { s = decodeURIComponent(s) } catch (e) {}
    return s
  }

  readonly property string officePath: fileUrlToPath(Qt.resolvedUrl("data/office.json"))
  readonly property string prayersPath: fileUrlToPath(Qt.resolvedUrl("data/prayers.json"))
  readonly property string outlinePath: fileUrlToPath(Qt.resolvedUrl("data/outline.json"))
  readonly property string helperPath: fileUrlToPath(Qt.resolvedUrl("bin/omarchy-catholic"))

  readonly property var schedule: Model.scheduleState(clock.date, settings)
  readonly property var currentHour: schedule.current
  readonly property var nextHour: schedule.next
  readonly property var featured: Model.featuredHour(schedule)
  readonly property string heroMeta: Model.heroMeta(featured)
  readonly property string effectiveHourId: selectedHourId !== "" ? selectedHourId : (featured ? featured.id : "morning")
  readonly property var office: Model.buildOffice(clock.date, Model.hourById(effectiveHourId), officeBook)
  readonly property var lectionary: Model.lectionaryCycle(clock.date)
  readonly property string todayIso: Model.isoDate(clock.date)
  readonly property string statusText: lastError !== "" ? lastError : "Catholic Reference"
  readonly property string tooltipText: {
    if (nextHour) {
      var until = Model.formatUntil(schedule.nowMinutes, nextHour.minutes, nextHour.tomorrow)
      return nextHour.name + " " + until + " (" + nextHour.time + ")"
    }
    return "Catholic Reference"
  }

  property var officeBook: ({})
  property string lastError: ""

  property var prayers: ({ prayers: [] })
  property string prayersError: ""

  property var readings: null
  property string readingsError: ""
  property bool readingsLoading: false

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  function parse(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (e) { return fallback }
  }

  function loadReadings(force) {
    if (root.readingsLoading) return
    if (!force && root.readings && root.readings.date === root.todayIso) return
    root.readingsLoading = true
    root.readingsError = ""
    readingsProc.command = [root.helperPath, "readings"].concat(force === true ? ["--refresh"] : [])
    readingsProc.running = true
  }

  property FileView officeFile: FileView {
    path: root.officePath
    printErrors: false
    onLoaded: {
      root.officeBook = root.parse(text(), {})
      root.lastError = ""
    }
    onLoadFailed: root.officeBook = ({})
  }

  property FileView prayersFile: FileView {
    path: root.prayersPath
    printErrors: false
    onLoaded: {
      root.prayers = root.parse(text(), { prayers: [] })
      root.prayersError = ""
    }
    onLoadFailed: root.prayersError = "Couldn't load the bundled prayers."
  }

  // Browse outlines for the Bible and Catechism tabs (tools/build-outline.mjs).
  property var outline: ({ bible: [], catechism: [] })
  property FileView outlineFile: FileView {
    path: root.outlinePath
    printErrors: false
    onLoaded: root.outline = root.parse(text(), { bible: [], catechism: [] })
  }

  property Process readingsProc: Process {
    id: readingsProc
    running: false
    stdout: StdioCollector {
      id: readingsOutput
      waitForEnd: true
    }
    onExited: function() {
      root.readingsLoading = false
      var raw = String(readingsOutput.text || "")
      if (raw.length > 262144) {
        root.readingsError = "Readings response was too large."
        return
      }
      var data = root.parse(raw, null)
      if (data && !data.error) {
        root.readings = data
        root.readingsError = ""
      } else {
        root.readingsError = data && data.error ? String(data.error) : "Couldn't load today's readings."
      }
    }
  }

  Component.onCompleted: {
    officeFile.reload()
    prayersFile.reload()
  }
}
