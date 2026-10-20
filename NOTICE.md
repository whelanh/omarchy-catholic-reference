# Data sources and attribution

This plugin bundles public-domain / freely-licensed corpora. The Readings tab
fetches the day's Mass readings from universalis.com; the Saint tab uses
bundled calendar and biography data generated from romcal, daily-saints and
catholic-readings-api.

## Douay-Rheims Bible (Challoner revision)

- Source: [scrollmapper/bible_databases](https://github.com/scrollmapper/bible_databases),
  `formats/json/DRC.json`.
- The Douay-Rheims Bible (Challoner revision) is in the public domain.
- The bundled `data/bible.tsv` index contains the 73 books of the Catholic
  canon. The five apocryphal appendices present in the source (`Prayer of
  Manasses`, `1 Esdras`, `2 Esdras`, `Additional Psalm`, `Laodiceans`) are
  omitted so the index matches the Catholic canon.
- Psalm numbers follow the Douay-Rheims (Vulgate) numbering, which differs by
  one from the modern Hebrew numbering for many psalms (e.g. "The Lord is my
  shepherd" is Psalm 22 in the Douay-Rheims).
- Regenerate the index with: `node tools/build-data.mjs path/to/DRC.json`.

## Catena Aurea commentary (four Gospels)

- Source: the public-domain OSIS XML at
  [lemtom/catena](https://github.com/lemtom/catena) (`catena.xml`), which is
  the source of the CrossWire SWORD `Catena` module.
- The Catena Aurea ("Golden Chain") is St. Thomas Aquinas' compilation of
  patristic quotations on Matthew, Mark, Luke, and John, in Blessed John
  Henry Newman's 1842 English translation. The text is public domain.
- The bundled `data/catena.json.gz` is a gzip-compressed verse-range index
  (commentator names and quotations per passage).
- Regenerate with: `node tools/build-catena.mjs path/to/catena.xml`.

## Catechism of the Catholic Church

- Source: [aseemsavio/catholicism-in-json](https://github.com/aseemsavio/catholicism-in-json),
  release `v2.0.0/catechism.json`.
- The Catechism text was prepared from the Catebot project
  (https://github.com/konohitowa/catebot). See that project for the applicable
  terms; the text is reproduced here for personal study and reference.

- The browse outline in `data/outline.json` (Parts, Sections, Chapters,
  Articles, their sub-headings and paragraph ranges) was taken from the table
  of contents with paragraph numbers published by Saint Charles Borromeo
  Catholic Church, Picayune, MS
  (https://www.scborromeo.org/ccc/ccc_toc2.htm). Two ranges there overlap by
  one paragraph; the build ends each entry where the next begins.
- Regenerate with: `node tools/build-outline.mjs path/to/ccc_toc2.htm`.

## Liturgy of the Hours (bundled office)

- Psalm texts, the Gospel canticles (Benedictus, Magnificat, Nunc dimittis),
  and the short scripture readings are extracted verbatim from the
  public-domain Douay-Rheims text.
- The Glory Be, the Lord's Prayer, and the opening and dismissal versicles are
  traditional public-domain texts.
- Hymns, intercessions, and collects are original compositions written for
  this plugin and are MIT-licensed.
- The liturgical calendar is a simplified approximation of the General Roman
  Calendar (Ordinary Form) intended for personal devotion, not for official
  liturgical use.
- Regenerate with: `node tools/build-office.mjs path/to/DRC.json`.

## Prayers

- `data/prayers.json` is the user's own `catholic_prayers.json` — common
  Catholic prayers in English and Latin. These are traditional public-domain
  texts.

## Daily Mass readings

- Fetched from [universalis.com](https://universalis.com/) (United States
  calendar) and cached under `~/.local/state/omarchy/catholic-reference/`.
- Readings are the Jerusalem Bible (© 1966, 1967, 1968 Hodder & Stoughton and
  Doubleday) and the Grail Psalms (© 1963), used at Mass in much of the
  English-speaking world. Full notices are shown on universalis.com.
- The Lectionary cycle (Year A/B/C and Weekday I/II) is computed locally in
  `Model.js`.
- The Collect is not shown because it is not available from the free sources.

## Today's liturgical celebration

- The calendar comes from [romcal](https://github.com/romcal/romcal) (MIT),
  generated at build time for 2026–2040 with the United States calendar. It
  supplies the celebration name, rank (including optional memorials), colour,
  and season.
- Biographies are matched by name from two MIT sources:
  - [daily-saints](https://github.com/ACoci86/daily-saints): summaries,
    legacy, patronage, era, and Wikipedia links. Its images are not used yet;
    when they are, `IMAGE-CREDITS.md` in that repository records each image's
    Commons source, licence, and author.
  - [catholic-readings-api](https://github.com/cpbjr/catholic-readings-api):
    quotations and short descriptions, especially for modern saints.
- Matching is by normalised saint name, not by those sources' own calendars,
  so the modern romcal date is authoritative.
- The **Franciscan Media** link points to
  [their saint of the day](https://www.franciscanmedia.org/saint-of-the-day/).
  Only a link is used; no Franciscan Media content is copied.
- No images are fetched or displayed in this version.
- The data is for personal devotion and reference; verify official liturgical
  details against the USCCB or the local diocese.
- Regenerate with `npm install --prefix tools && node tools/build-calendar.mjs`.
