// Regenerate data/outline.json: the browse outlines for the Bible and the
// Catechism tabs.
//
//   node tools/build-outline.mjs path/to/ccc_toc2.htm
//
// The Catechism outline comes from the St. Charles Borromeo parish table of
// contents with paragraph numbers (https://www.scborromeo.org/ccc/ccc_toc2.htm),
// saved locally. Each entry there is a paragraph range followed by a title.
// Parts, Sections, Chapters, Articles and "Paragraph n." entries become
// browsable nodes nested by range; the numbered sub-headings inside them
// ("I. The Desire for God", "IN BRIEF") become headings shown while reading.
//
// Bible divisions follow the Douay-Rheims order; chapter counts are read
// from data/bible.tsv.

import { readFileSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..")

const BIBLE = [
  ["Old Testament", [
    ["Pentateuch", ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"]],
    ["Historical Books", ["Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra", "Nehemiah", "Tobit", "Judith", "Esther", "1 Maccabees", "2 Maccabees"]],
    ["Wisdom Books", ["Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Songs", "Wisdom", "Sirach"]],
    ["Major Prophets", ["Isaiah", "Jeremiah", "Lamentations", "Baruch", "Ezekiel", "Daniel"]],
    ["Minor Prophets", ["Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi"]],
  ]],
  ["New Testament", [
    ["Gospels", ["Matthew", "Mark", "Luke", "John"]],
    ["Acts of the Apostles", ["Acts"]],
    // The Douay-Rheims titles Hebrews "The Epistle of St. Paul to the Hebrews".
    ["Letters of St. Paul", ["Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews"]],
    ["Catholic Letters", ["James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude"]],
    ["Revelation", ["Revelation"]],
  ]],
]

// Printed as verse lines rather than running prose.
const POETIC = ["Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Songs", "Wisdom", "Sirach", "Lamentations"]

function chapterCounts() {
  const counts = {}
  for (const line of readFileSync(join(ROOT, "data", "bible.tsv"), "utf8").split("\n")) {
    const [book, ref] = line.split("\t")
    if (!ref) continue
    const chapter = parseInt(ref, 10)
    counts[book] = Math.max(counts[book] || 0, chapter)
  }
  return counts
}

const SMALL = new Set(["a", "an", "and", "as", "at", "by", "for", "from", "in", "into", "of", "on", "or", "the", "to", "with"])

// "CHAPTER ONE: MAN'S CAPACITY FOR GOD" -> "Chapter One: Man's Capacity for God"
function titleCase(s) {
  if (s !== s.toUpperCase()) return s
  let first = true
  return s.toLowerCase().replace(/[a-z][a-z']*/g, (w, i) => {
    const after = s.slice(Math.max(0, i - 2), i)
    const start = first || /[:\-"“(]\s*$/.test(after)
    first = false
    return !start && SMALL.has(w) ? w : w[0].toUpperCase() + w.slice(1)
  })
}

function parseToc(htmlPath) {
  const raw = readFileSync(htmlPath, "latin1")
  const text = raw.replace(/<[^>]+>/g, "\n")
    .replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(parseInt(n, 10)))
  const lines = text.split("\n").map((l) => l.replace(/\s+/g, " ").trim()).filter(Boolean)
  const items = []
  for (let i = 0; i + 1 < lines.length; i++) {
    const m = lines[i].match(/^(\d+)(?:\s*-\s*(\d+))?$/)
    if (!m) continue
    const a = parseInt(m[1], 10)
    items.push({ a, b: m[2] ? parseInt(m[2], 10) : a, title: lines[i + 1] })
    i++
  }
  return items
}

function isHeading(title) {
  return /^([IVX]+\.|IN BRIEF\b)/i.test(title)
}

function buildCatechism(items) {
  const root = { c: [] }
  const stack = [{ a: 0, b: Infinity, node: root }]
  const headings = []
  for (const it of items) {
    while (!(stack[stack.length - 1].a <= it.a && it.b <= stack[stack.length - 1].b)) stack.pop()
    if (isHeading(it.title)) {
      headings.push([it.a, titleCase(it.title)])
      continue
    }
    const node = { t: titleCase(it.title), a: it.a, b: it.b, c: [] }
    stack[stack.length - 1].node.c.push(node)
    stack.push({ a: it.a, b: it.b, node })
  }
  // Paragraphs a node covers but none of its children do (a Part's opening
  // paragraphs, say) become their own entries, so browsing reaches all 2865.
  const fill = (n) => {
    if (!n.c || n.c.length === 0) { delete n.c; return }
    // The source overlaps two siblings by one paragraph (e.g. "Heaven and
    // Earth" ends at 355, where "Man" begins); an entry ends where the next starts.
    for (let i = 0; i + 1 < n.c.length; i++) {
      if (n.c[i].b >= n.c[i + 1].a) n.c[i].b = n.c[i + 1].a - 1
    }
    const kids = []
    let next = n.a
    const gap = (a, b) => kids.push({ t: kids.length === 0 ? "Introduction" : `Paragraphs ${a}–${b}`, a, b })
    for (const k of n.c) {
      if (k.a > next) gap(next, k.a - 1)
      kids.push(k)
      next = Math.max(next, k.b + 1)
    }
    if (next <= n.b) gap(next, n.b)
    n.c = kids
    n.c.forEach(fill)
  }
  root.c.forEach(fill)
  return { tree: root.c, headings }
}

const tocPath = process.argv[2]
if (!tocPath) {
  console.error("usage: node tools/build-outline.mjs path/to/ccc_toc2.htm")
  process.exit(2)
}
const counts = chapterCounts()
const bible = BIBLE.map(([name, divisions]) => ({
  name,
  divisions: divisions.map(([dname, books]) => ({
    name: dname,
    books: books.map((b) => {
      if (!counts[b]) throw new Error("book missing from bible.tsv: " + b)
      return { name: b, chapters: counts[b] }
    }),
  })),
}))
const catechism = buildCatechism(parseToc(tocPath))
const out = { bible, poetic: POETIC, catechism: catechism.tree, catechismHeadings: catechism.headings }
writeFileSync(join(ROOT, "data", "outline.json"), JSON.stringify(out) + "\n")
console.log(`wrote data/outline.json: ${bible.reduce((n, t) => n + t.divisions.reduce((m, d) => m + d.books.length, 0), 0)} books, ${catechism.tree.length} top-level Catechism nodes, ${catechism.headings.length} headings`)
