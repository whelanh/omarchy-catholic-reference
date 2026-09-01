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

function cleanBody(body) {
  // Drop the verse-quote paragraph(s) (the <p osisID="..."> blocks).
  let text = body.replace(/<p[^>]*osisID="[^"]*"[^>]*>[\s\S]*?<\/p>/g, " ")
  // Paragraphs -> newlines, inline markup removed.
  text = text.replace(/<p[^>]*>/g, "\n").replace(/<\/p>/g, "\n")
  text = decodeHtml(text)
  text = text.replace(/[ \t]+/g, " ")
  text = text.replace(/\n[ \t]*/g, "\n")
  text = text.replace(/\n{3,}/g, "\n\n")
  return text.trim()
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
    const text = cleanBody(m[2])
    if (!text) continue
    sections.push({ b: ref.b, c: ref.c, s: ref.s, e: ref.e, t: text })
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
