# Catholic Reference for Omarchy

An Omarchy Quattro bar widget with a theme-colored Chi-Rho icon and a
six-tab panel: fuzzy search of the **Douay-Rheims Bible** (with **Catena
Aurea** commentary), the **Catechism of the Catholic Church**, common
**Catholic prayers**, the daily **Mass readings** (with a guided **Lectio
Divina**), a bundled **Liturgy of the Hours**, and **today's saint and
liturgical celebration**.

Plugin id: `io.github.whelanh.catholic-reference`

## What it does

- **Bible tab** — search the full 73-book Douay-Rheims (Challoner) text by
  word, phrase, or reference. Search is fuzzy: type `god so loved` and
  John 3:16 comes back without needing the exact wording. Book names work
  as you type them: `Mat` lists the chapters of Matthew, `Mat 4` shows the
  whole chapter, `Mat 4:23` the verse, and `Mat 4:23-25` a range. A short
  prefix like `Jo` offers every book it could mean; select a book or chapter
  to open it. Click a result to copy it and
  pin it with **Catena Aurea** commentary (Thomas Aquinas' Golden Chain, on
  the four Gospels); the `random` chip does the same for a random passage.
  `Esc` or Back returns to the results.
- **Catechism tab** — fuzzy search all 2865 paragraphs of the Catechism of
  the Catholic Church. Click a paragraph to copy it with its CCC number.
- **Prayers tab** — the bundled `data/prayers.json` (Our Father, Hail Mary,
  Glory Be, the Apostles' Creed, and more) in English and Latin.
- **Readings tab** — today's Mass readings (First Reading, Responsorial
  Psalm, Second Reading, Gospel Acclamation, Gospel) with the liturgical
  colour and the Lectionary cycle (Year A/B/C and Weekday I/II). Fetched
  from universalis.com and cached locally for offline reuse. **Pray with
  today's Gospel** opens a four-step **Lectio Divina** (Lectio, Meditatio,
  Oratio, Contemplatio) using the Douay-Rheims text, with Catena Aurea
  excerpts during Meditatio.
- **Saint tab** — today's liturgical celebration from a bundled romcal
  calendar (accurate modern US calendar, including optional memorials), with
  the saint or feast, its rank and season, a quotation, and a biography
  matched by name from bundled daily-saints and catholic-readings-api data.
  On ferias and Sundays it names the liturgical day. Fully offline, with links
  to Franciscan Media and Wikipedia. No images are loaded.
- **Hours tab** — the office for Morning, Daytime, Evening, and Night Prayer.
  The current hour is highlighted and selected by default; the liturgical day
  (General Roman Calendar, approximated) is shown above the text.
- **Browse** — with nothing typed, the Bible tab opens on the Old and New
  Testaments by division (Pentateuch, Historical Books, Wisdom Books, the
  Prophets; Gospels, Acts, Letters of St. Paul, Catholic Letters,
  Revelation), and the Catechism tab on its Prologue and four Parts down to
  each Article, with paragraph numbers. Open a chapter or section to read it
  as running text; ‹ › step to the next one. In a chapter, click a verse
  number for its card and Catena Aurea commentary; in the Catechism, click a
  paragraph number to copy it, or a cross-reference to follow it.
- **Pop out** — the header's **Pop out** button moves the reader into a
  resizable window with room for longer passages. Closing the window returns
  it to the bar popup. Scriptable too:
  `qs ipc -p /usr/share/omarchy/shell call io.github.whelanh.catholic-reference window`.

Everything runs offline except the Readings tab, which makes one request to
universalis.com the first time it is opened each day and then reads a local
cache. The Saint tab is fully offline. The Collect is not shown: it is not
available from the free sources.

## Install

```bash
omarchy plugin add https://github.com/whelanh/omarchy-catholic-reference.git --enable
omarchy bar move io.github.whelanh.catholic-reference --section right
```

No extra packages to install: the search and readings helper
`bin/omarchy-catholic` is a Python 3 script, and Python 3 and `wl-clipboard`
(for copying results) are both part of Omarchy. The Readings tab needs network
access; everything else is fully offline.

## Usage

- **Left click** the Chi-Rho in the bar to open or close the panel.
- **Bible / Catechism tabs:** type to search (fuzzy, debounced). `↑`/`↓` move
  the cursor, `Enter` copies the selected result, `Esc` returns focus from the
  search field, then `Esc` closes the panel. In the Bible tab, `Enter` or a
  click pins the verse with commentary; `Esc`/Back returns to the list.
- **Prayers tab:** click a prayer to read it in English and Latin.
- **Readings tab:** today's Mass readings load automatically; click Refresh to
  force a re-fetch. Click **Pray with today's Gospel** for the guided Lectio
  Divina.
- **Lectio Divina:** step through Read / Reflect / Respond / Rest, or click a
  step name to jump. The passage is the public-domain Douay-Rheims text;
  Meditatio includes Catena Aurea excerpts for Gospel passages.
- **Saint tab:** today's celebration and biography are bundled; use the
  Franciscan Media or Wikipedia buttons to read more.
- **Hours tab:** click Morning / Daytime / Evening / Night to read that hour's
  office. Scroll to see the full text.
- `Tab` / `Shift+Tab` switches to the neighbouring bar panel.

## Data and privacy

- The Douay-Rheims Bible is public domain; the search index is `data/bible.tsv`.
- The Catena Aurea commentary (four Gospels) is bundled, gzip-compressed, as
  `data/catena.json.gz`; it is public domain.
- The Catechism is bundled as `data/catechism.json`.
- The office (psalms, canticles, readings, collects) is bundled as
  `data/office.json`.
- Prayers are bundled as `data/prayers.json`.
- Mass readings are fetched from universalis.com and cached under
  `~/.local/state/omarchy/catholic-reference/` (one request per day).
- Today's celebration and biography come from bundled data
  (`data/calendar.json.gz`, generated from romcal; `data/saints.json.gz`,
  matched by name from daily-saints and catholic-readings-api). The Saint tab
  makes no network requests.
- The Lectio Divina prompts are original to this plugin; the scripture is the
  bundled Douay-Rheims text and the commentary is the public-domain Catena
  Aurea. No additional network request is made.
- Does not request elevated privileges, runs no background services, and starts no second Quickshell process.

## Regenerating the data

The bundled data can be rebuilt from the upstream sources. These are
maintainer-only scripts and require Node; they are not part of the plugin's
runtime or installation.

```bash
node tools/build-data.mjs path/to/DRC.json      # writes data/bible.tsv + data/books.json
node tools/build-office.mjs path/to/DRC.json    # writes data/office.json
node tools/build-catena.mjs path/to/catena.xml  # writes data/catena.json.gz
npm install --prefix tools
node tools/build-calendar.mjs                   # writes data/calendar.json.gz + data/saints.json.gz
```

`DRC.json` is the `formats/json/DRC.json` file from the
[scrollmapper/bible_databases](https://github.com/scrollmapper/bible_databases)
repository. `catena.xml` is the OSIS source from
[lemtom/catena](https://github.com/lemtom/catena). See [NOTICE.md](NOTICE.md)
for sources and licensing.

## Development checks

```bash
omarchy plugin validate .
python3 -m py_compile bin/omarchy-catholic
node tests/model.test.js
node tests/search.test.js
node tests/reader.test.js
node tests/saint.test.js
node tests/lectio.test.js
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Service.qml ChiRho.qml
```

The `node` commands above, and the data-regeneration scripts under `tools/`,
are optional maintainer-only checks; they are not needed to install or run the
plugin.

## Remove

```bash
omarchy plugin remove io.github.whelanh.catholic-reference
```

## Contributors
[Hugh Whelan](https://github.com/whelanh) — project author and maintainer.

[Demian Neidetcher](https://github.com/demian0311) — Browse the Bible and Catechism by outline and read them as running text(#5).

## License

Plugin code is MIT licensed. See [LICENSE](LICENSE). Data sources are covered
in [NOTICE.md](NOTICE.md).
