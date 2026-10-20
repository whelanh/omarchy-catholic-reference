#!/usr/bin/env node
// Maintainer-only data generation for the Catholic Reference plugin.
//
// Produces two bundled files:
//   data/calendar.json.gz  accurate modern (US) liturgical calendar from romcal
//   data/saints.json.gz    name-keyed biographies merged from daily-saints and
//                          the catholic-readings-api
//
// The plugin only reads these files at runtime; Node and these packages are
// not needed to install or use the plugin. Install the packages declared in
// tools/package.json, then run:
//
//   node tools/build-calendar.mjs

import { Romcal } from "romcal"
import { UnitedStates_En } from "@romcal/calendar.united-states"
import { gzipSync } from "node:zlib"
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const DATA = resolve(ROOT, "data")
const CACHE = resolve(ROOT, "tools", ".cache")

const START_YEAR = 2026
const END_YEAR = 2040
const CPBJR_YEARS = ["2025", "2026", "2027"]

const DAILY_SAINTS = "https://acoci86.github.io/daily-saints"
const CPBJR_API = "https://api.github.com/repos/cpbjr/catholic-readings-api"
const CPBJR_RAW = "https://raw.githubusercontent.com/cpbjr/catholic-readings-api/main"

// Name variants used by the three sources. Keys and values are normalised
// names; both the source name and the canonical name are indexed so the
// runtime only has to normalise the romcal name.
const ALIASES = {
  "jean de brebeuf": "john de brebeuf",
  "jean de brebeuf and isaac jogues": "john de brebeuf and isaac jogues",
  "john cantius": "john of kanty",
  "therese of lisieux": "therese of the child jesus",
  "alphonsus liguori": "alphonsus mary liguori",
  "john vianney": "john mary vianney",
  "pio of pietrelcina": "pius of pietrelcina",
  "padre pio": "pius of pietrelcina",
  "teresa of avila": "teresa of jesus",
  "pope john paul ii": "john paul ii",
  "pope paul vi": "paul vi",
}

function normalizeName(name) {
  let s = String(name || "")
  s = s.normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
  s = s.toLowerCase()
  s = s.replace(/\([^)]*\)/g, " ")
  s = s.replace(/^\s*(pope\s+)?saints?\b\.?\s*/, "")
  s = s.replace(/^\s*(blessed|saint)\b\.?\s*/, "")
  s = s.split(",")[0]
  s = s.replace(/\band\s+(his\s+|her\s+)?companions?\b/g, " ")
  s = s.replace(/[^a-z0-9]+/g, " ")
  return s.replace(/\s+/g, " ").trim().replace(/^the\s+/, "")
}

function keysForName(name) {
  const base = normalizeName(name)
  if (!base) return []
  const keys = new Set([base])
  if (ALIASES[base]) keys.add(ALIASES[base])
  return [...keys]
}

function writeGzip(path, text) {
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, gzipSync(text, { level: 9 }))
  return gzipSync(text, { level: 9 }).length
}

async function getText(url, cachePath) {
  if (existsSync(cachePath)) return readFileSync(cachePath, "utf8")
  const response = await fetch(url, { headers: { "User-Agent": "omarchy-catholic-reference-build" } })
  if (!response.ok) throw new Error(`${response.status} ${url}`)
  const text = await response.text()
  mkdirSync(dirname(cachePath), { recursive: true })
  writeFileSync(cachePath, text)
  return text
}

async function getJson(url, cachePath) {
  return JSON.parse(await getText(url, cachePath))
}

async function mapLimit(items, limit, fn) {
  let next = 0
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++
      await fn(items[index], index)
    }
  })
  await Promise.all(workers)
}

function mergeEntry(index, name, source, entry) {
  for (const key of keysForName(name)) {
    const current = index[key]
    if (!current) {
      index[key] = { ...entry, sources: [source] }
      continue
    }
    if (!current.name && entry.name) current.name = entry.name
    if (!current.summary && entry.summary) current.summary = entry.summary
    if (!current.quote && entry.quote) current.quote = entry.quote
    if (!current.legacy && entry.legacy) current.legacy = entry.legacy
    if (!current.era && entry.era) current.era = entry.era
    if (!current.wikipedia && entry.wikipedia) current.wikipedia = entry.wikipedia
    if (!current.image && entry.image) current.image = entry.image
    if (!current.imageCredit && entry.imageCredit) current.imageCredit = entry.imageCredit
    if ((!current.patronage || current.patronage.length === 0) && entry.patronage) current.patronage = entry.patronage
    if (entry.summary && entry.summary.length > (current.summary || "").length) current.summary = entry.summary
    if (!current.sources.includes(source)) current.sources.push(source)
  }
}

async function buildCalendar() {
  const romcal = new Romcal({ localizedCalendar: UnitedStates_En })
  const out = {}

  for (let year = START_YEAR; year <= END_YEAR; year++) {
    const generated = await romcal.generateCalendar(year)
    for (const [date, entries] of Object.entries(generated)) {
      out[date] = entries.map((entry) => ({
        name: entry.name,
        rank: entry.rank,
        rankName: entry.rankName,
        optional: !!entry.isOptional,
        colors: entry.colors || [],
        season: (entry.seasonNames || [])[0] || "",
      }))
    }
  }

  const sorted = Object.fromEntries(Object.keys(out).sort().map((key) => [key, out[key]]))
  const size = writeGzip(resolve(DATA, "calendar.json.gz"), JSON.stringify(sorted))
  console.log(`calendar: ${Object.keys(sorted).length} dates, ${size} gz bytes`)
}

function parseImageCredits(text) {
  const credits = {}
  for (const line of text.split("\n")) {
    if (!line.startsWith("|")) continue
    const cells = line.split("|").slice(1, -1).map((cell) => cell.trim())
    if (cells.length < 5) continue
    if (cells[0].toLowerCase() === "saint" || /^-+$/.test(cells[0])) continue
    const file = (cells[1].match(/`([^`]+)`/) || [])[1]
    if (!file) continue
    const source = (cells[2].match(/\((https?:\/\/[^)]+)\)/) || [])[1] || ""
    credits[file] = { source, license: cells[3], author: cells[4] }
  }
  return credits
}

async function buildDailySaints(index) {
  const credits = parseImageCredits(
    await getText(`${DAILY_SAINTS}/IMAGE-CREDITS.md`, resolve(CACHE, "daily-saints", "IMAGE-CREDITS.md")),
  )

  const days = []
  const start = Date.UTC(2024, 0, 1) // leap year, so 02-29 is included
  for (let i = 0; i < 366; i++) {
    const date = new Date(start + i * 86_400_000)
    days.push(`${String(date.getUTCMonth() + 1).padStart(2, "0")}-${String(date.getUTCDate()).padStart(2, "0")}`)
  }

  await mapLimit(days, 16, async (day) => {
    const data = await getJson(
      `${DAILY_SAINTS}/api/v1/saints/${day}.json`,
      resolve(CACHE, "daily-saints", `${day}.json`),
    )
    for (const saint of data.saints || []) {
      const image = saint.image ? String(saint.image).split("/").pop() : ""
      mergeEntry(index, saint.name, "daily-saints", {
        name: saint.name,
        summary: saint.summary || "",
        legacy: saint.legacy || "",
        patronage: saint.patronage || [],
        era: saint.era || "",
        wikipedia: saint.wikipedia || "",
        image,
        imageCredit: credits[image] || null,
      })
    }
  })
}

async function buildCpbjr(index) {
  const tree = await getJson(`${CPBJR_API}/git/trees/main?recursive=1`, resolve(CACHE, "cpbjr-tree.json"))
  const pattern = new RegExp(`^liturgical-calendar/(${CPBJR_YEARS.join("|")})/\\d{2}-\\d{2}\\.json$`)
  const paths = (tree.tree || [])
    .filter((item) => item.type === "blob" && pattern.test(item.path))
    .map((item) => item.path)

  await mapLimit(paths, 16, async (path) => {
    const data = await getJson(`${CPBJR_RAW}/${path}`, resolve(CACHE, "cpbjr", path))
    const celebration = data.celebration || {}
    const name = String(celebration.name || "").trim()
    // Entries combining two celebrations ("A/B") are the API's date bug; skip
    // them rather than attributing one saint's biography to another.
    if (!name || name.includes("/")) return
    const quote = String(celebration.quote || "").trim()
    const description = String(celebration.description || "").trim()
    const wikipedia = String(data.wikipediaLink || "").trim()
    if (!quote && !description && !wikipedia) return
    mergeEntry(index, name, "cpbjr", {
      name,
      quote,
      summary: description,
      wikipedia,
    })
  })
}

async function main() {
  mkdirSync(DATA, { recursive: true })
  mkdirSync(CACHE, { recursive: true })

  await buildCalendar()

  const index = {}
  await buildDailySaints(index)
  await buildCpbjr(index)

  const sorted = Object.fromEntries(Object.keys(index).sort().map((key) => [key, index[key]]))
  const size = writeGzip(resolve(DATA, "saints.json.gz"), JSON.stringify(sorted))
  console.log(`saints: ${Object.keys(sorted).length} keys, ${size} gz bytes`)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
