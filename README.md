# Catholic Reference for Omarchy

An Omarchy Quattro bar widget with a theme-colored Chi-Rho icon and a
five-tab panel: fuzzy search of the **Douay-Rheims Bible** (with **Catena
Aurea** commentary), the **Catechism of the Catholic Church**, common
**Catholic prayers**, the daily **Mass readings**, and a bundled **Liturgy of
the Hours**.

Plugin id: `io.github.whelanh.catholic-reference`

## What it does

- **Bible tab** — search the full 73-book Douay-Rheims (Challoner) text by
  word, phrase, or reference. Search is fuzzy: type `god so loved` and
  John 3:16 comes back without needing the exact wording. References like
  `John 3:16` or `Genesis 1` resolve directly. Click a result to copy it and
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
  from universalis.com and cached locally for offline reuse.
- **Hours tab** — the office for Morning, Daytime, Evening, and Night Prayer.
  The current hour is highlighted and selected by default; the liturgical day
  (General Roman Calendar, approximated) is shown above the text.

Everything runs offline except the Readings tab, which makes one request to
universalis.com the first time it is opened each day and then reads a local
cache. The Collect is not shown: it is not available from the free sources.

## Install

```bash
omarchy plugin add https://github.com/whelanh/omarchy-catholic-reference.git --enable
omarchy bar move io.github.whelanh.catholic-reference --section right
```

Requires `node` (the search/readings helper `bin/omarchy-catholic` is a Node
script) and `wl-clipboard` for copying results. The Readings tab needs
network access; everything else is fully offline.

## Usage

- **Left click** the Chi-Rho in the bar to open or close the panel.
- **Bible / Catechism tabs:** type to search (fuzzy, debounced). `↑`/`↓` move
  the cursor, `Enter` copies the selected result, `Esc` returns focus from the
  search field, then `Esc` closes the panel. In the Bible tab, `Enter` or a
  click pins the verse with commentary; `Esc`/Back returns to the list.
- **Prayers tab:** click a prayer to read it in English and Latin.
- **Readings tab:** today's Mass readings load automatically; click Refresh to
  force a re-fetch.
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
- Does not request elevated privileges, runs no background services, and starts no second Quickshell process.

## Regenerating the data

The bundled data can be rebuilt from the upstream sources:

```bash
node tools/build-data.mjs path/to/DRC.json      # writes data/bible.tsv + data/books.json
node tools/build-office.mjs path/to/DRC.json    # writes data/office.json
node tools/build-catena.mjs path/to/catena.xml  # writes data/catena.json.gz
```

`DRC.json` is the `formats/json/DRC.json` file from the
[scrollmapper/bible_databases](https://github.com/scrollmapper/bible_databases)
repository. `catena.xml` is the OSIS source from
[lemtom/catena](https://github.com/lemtom/catena). See [NOTICE.md](NOTICE.md)
for sources and licensing.

## Development checks

```bash
omarchy plugin validate .
node tests/model.test.js
node --check bin/omarchy-catholic
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Service.qml ChiRho.qml
```

## Remove

```bash
omarchy plugin remove io.github.whelanh.catholic-reference
```

## License

Plugin code is MIT licensed. See [LICENSE](LICENSE). Data sources are covered
in [NOTICE.md](NOTICE.md).
