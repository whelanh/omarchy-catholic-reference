// Build data/catena.json.gz: the Catena Aurea (Thomas Aquinas / J.H. Newman)
// commentary on the four Gospels, as a compact verse-range index.
//
//   node tools/build-catena.mjs path/to/catena.xml
//
// Input: the public-domain OSIS XML from https://github.com/lemtom/catena
// (catena.xml). Output is a gzipped JSON array of:
//   { "b": "Matthew", "c": 1, "s": 3, "e": 5, "t": "commentary text" }
// where s/e are the inclusive start/end verse of the commented passage.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs"
import { gzipSync } from "node:zlib"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..")

const BOOK_NAMES = {
  Matt: "Matthew",
  Mark: "Mark",
  Luke: "Luke",
  John: "John",
}

function decodeHtml(s) {
  return String(s)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&#8217;|&#39;|&apos;/g, "'")
    .replace(/&#8211;/g, "\u2013")
    .replace(/&#8212;/g, "\u2014")
    .replace(/&#160;/g, " ")
    .replace(/&#8220;|&#8221;/g, '"')
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&nbsp;/g, " ")
}

function parseRef(ref) {
  // "Matt.1.1" or "Matt.1.3-Matt.1.5"
  const m = ref.match(/^([A-Za-z]+)\.(\d+)\.(\d+)(?:-[A-Za-z]+\.\d+\.(\d+))?$/)
  if (!m) return null
  const book = BOOK_NAMES[m[1]]
  if (!book) return null
  const start = parseInt(m[3], 10)
  const end = m[4] ? parseInt(m[4], 10) : start
  return { b: book, c: parseInt(m[2], 10), s: start, e: end }
}

// Split a section body into [author, text] paragraphs. The verse-quote
// paragraphs (<p osisID="...">) are dropped; the bold author attribution in
// each remaining paragraph becomes a separate leading field so the panel can
// render it in bold.
function parseParagraphs(body) {
  let src = body.replace(/<p[^>]*osisID="[^"]*"[^>]*>[\s\S]*?<\/p>/g, "")
  const paras = []
  const pRe = /<p[^>]*>([\s\S]*?)<\/p>/g
  let m
  while ((m = pRe.exec(src)) !== null) {
    let inner = m[1]
    const authorRe = /<hi type="bold">([\s\S]*?)<\/hi>/
    const am = inner.match(authorRe)
    let author = ""
    if (am) {
      author = decodeHtml(am[1]).replace(/\s+/g, " ").trim()
      inner = inner.replace(authorRe, " ")
    }
    const text = decodeHtml(inner).replace(/\s+/g, " ").trim()
    if (!author && !text) continue
    paras.push([author, text])
  }
  return paras
}

function main() {
  const input = process.argv[2]
  if (!input) {
    console.error("usage: node tools/build-catena.mjs path/to/catena.xml")
    process.exit(2)
  }
  const xml = readFileSync(input, "utf8")

  const sections = []
  const divRe = /<div annotateRef="([^"]+)" annotateType="commentary" type="section">([\s\S]*?)<\/div>/g
  let m
  while ((m = divRe.exec(xml)) !== null) {
    const ref = parseRef(m[1])
    if (!ref) continue
    const paras = parseParagraphs(m[2])
    if (paras.length === 0) continue
    sections.push({ b: ref.b, c: ref.c, s: ref.s, e: ref.e, p: paras })
  }

  sections.sort((a, b2) => {
    if (a.b !== b2.b) return a.b.localeCompare(b2.b)
    if (a.c !== b2.c) return a.c - b2.c
    return a.s - b2.s
  })

  const json = JSON.stringify(sections)
  const gz = gzipSync(json, { level: 9 })

  mkdirSync(join(ROOT, "data"), { recursive: true })
  writeFileSync(join(ROOT, "data", "catena.json.gz"), gz)

  const kb = (gz.length / 1024).toFixed(0)
  console.log(`wrote data/catena.json.gz (${sections.length} sections, ${kb} KB compressed, ${(json.length / 1024 / 1024).toFixed(2)} MB raw)`)
}

main()
