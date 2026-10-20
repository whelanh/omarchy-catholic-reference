// Today's celebration and bundled biographies. Run with: node tests/saint.test.js
const assert = require("assert")
const { execFileSync } = require("child_process")
const path = require("path")

const HELPER = path.join(__dirname, "..", "bin", "omarchy-catholic")

function saint(date) {
  return JSON.parse(execFileSync(HELPER, ["saint", date], { encoding: "utf8" }))
}

function test(name, fn) {
  try { fn(); console.log("ok - " + name) }
  catch (e) { console.error("FAIL - " + name); console.error(e); process.exitCode = 1 }
}

test("optional memorial is featured over the weekday", () => {
  const day = saint("2026-10-20")
  assert.strictEqual(day.featured, 1)
  assert.strictEqual(day.celebrations.length, 2)
  assert.match(day.celebrations[0].rank, /^WEEKDAY$/)
  assert.match(day.celebrations[1].name, /Paul of the Cross/)
  assert.strictEqual(day.celebrations[1].rank, "OPTIONAL_MEMORIAL")
  assert.ok(day.celebrations[1].summary.length > 20)
  assert.ok(day.celebrations[1].quote.length > 5)
  assert.match(day.celebrations[1].wikipedia, /^https:\/\/en\.wikipedia\.org\//)
})

test("memorial is featured and carries a biography", () => {
  const day = saint("2026-10-19")
  assert.strictEqual(day.featured, 0)
  assert.strictEqual(day.celebrations[0].rank, "MEMORIAL")
  assert.match(day.celebrations[0].name, /Br[eé]beuf/)
  assert.ok(day.celebrations[0].summary.length > 10)
})

test("a feria has no biography", () => {
  const day = saint("2026-10-21")
  assert.strictEqual(day.featured, 0)
  assert.strictEqual(day.celebrations.length, 1)
  assert.strictEqual(day.celebrations[0].rank, "WEEKDAY")
  assert.strictEqual(day.celebrations[0].summary, undefined)
})

test("a solemnity is identified", () => {
  const day = saint("2026-12-25")
  assert.strictEqual(day.celebrations[0].rank, "SOLEMNITY")
  assert.match(day.celebrations[0].name, /Nativity/)
  assert.ok(day.celebrations[0].summary.length > 10)
})

test("the Franciscan Media link is always present", () => {
  assert.strictEqual(saint("2026-10-21").learnMore, "https://www.franciscanmedia.org/saint-of-the-day/")
})

test("a year outside the bundled range reports an error", () => {
  const day = saint("2041-01-01")
  assert.match(day.error, /No calendar data/)
})
