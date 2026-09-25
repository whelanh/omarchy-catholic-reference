// Browse outline and reader commands. Run with: node tests/reader.test.js
const assert = require("assert")
const { execFileSync } = require("child_process")
const path = require("path")

const ROOT = path.join(__dirname, "..")
const outline = require(path.join(ROOT, "data", "outline.json"))

function helper(...args) {
  return JSON.parse(execFileSync("node", [path.join(ROOT, "bin", "omarchy-catholic"), ...args], { encoding: "utf8" }))
}

function test(name, fn) {
  try { fn(); console.log("ok - " + name) }
  catch (e) { console.error("FAIL - " + name); console.error(e); process.exitCode = 1 }
}

// Grouped by division, so 1-2 Maccabees sit with the Historical Books rather
// than at the end of the Old Testament as in books.json.
test("bible outline holds each of the 73 books once", () => {
  const books = outline.bible.flatMap((t) => t.divisions.flatMap((d) => d.books.map((b) => b.name)))
  const canon = require(path.join(ROOT, "data", "books.json")).map((b) => b.name)
  assert.deepStrictEqual([...books].sort(), [...canon].sort())
  assert.deepStrictEqual(outline.bible.map((t) => t.name), ["Old Testament", "New Testament"])
})

test("every Catechism paragraph is reachable exactly once", () => {
  const seen = []
  const walk = (nodes) => nodes.forEach((n) => {
    if (n.c) walk(n.c)
    else for (let i = n.a; i <= n.b; i++) seen.push(i)
  })
  walk(outline.catechism)
  assert.deepStrictEqual(seen, Array.from({ length: 2865 }, (_, i) => i + 1))
})

test("catechism outline starts with the Prologue and four Parts", () => {
  assert.deepStrictEqual(outline.catechism.map((n) => [n.a, n.b]),
    [[1, 25], [26, 1065], [1066, 1690], [1691, 2557], [2558, 2865]])
})

test("chapter command returns the chapter", () => {
  const d = helper("chapter", "Matthew", "5")
  assert.strictEqual(d.book, "Matthew")
  assert.strictEqual(d.chapters, 28)
  assert.strictEqual(d.verses.length, 48)
  assert.deepStrictEqual(d.verses[2][0], 3)
  assert.strictEqual(d.poetic, false)
  assert.strictEqual(helper("chapter", "Psalms", "22").poetic, true)
  assert.strictEqual(helper("chapter", "1", "Corinthians", "13").verses.length, 13)
})

test("ccc command returns paragraphs with their headings", () => {
  const d = helper("ccc", "27", "49")
  assert.strictEqual(d.paragraphs.length, 23)
  assert.deepStrictEqual(d.headings[0], [27, "I. The Desire for God"])
  assert.deepStrictEqual(d.headings[d.headings.length - 1], [44, "In Brief"])
})
