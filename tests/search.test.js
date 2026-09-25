// Book/chapter/verse navigation in the search helper. Run with: node tests/search.test.js
const assert = require("assert")
const { execFileSync } = require("child_process")
const path = require("path")

const HELPER = path.join(__dirname, "..", "bin", "omarchy-catholic")

function search(query) {
  return execFileSync("node", [HELPER, "search", "bible", query], { encoding: "utf8" })
    .split("\n").filter(Boolean).map((line) => line.split("\t"))
}

function rows(query, kind) { return search(query).filter((r) => r[0] === kind) }

function test(name, fn) {
  try { fn(); console.log("ok - " + name) }
  catch (e) { console.error("FAIL - " + name); console.error(e); process.exitCode = 1 }
}

test("prefix shared by several books offers each book", () => {
  assert.deepStrictEqual(rows("Ma", "NAV").map((r) => r[1]), ["Malachi", "Matthew", "Mark"])
  assert.strictEqual(rows("Ma", "NAV")[1][3], "Matthew ")
})

test("unique prefix lists every chapter", () => {
  const nav = rows("Mat", "NAV")
  assert.strictEqual(nav.length, 28)
  assert.deepStrictEqual([nav[3][1], nav[3][3]], ["Matthew 4", "Matthew 4"])
})

test("book and chapter shows the whole chapter", () => {
  assert.strictEqual(rows("Mat 4", "RESULT").length, 25)
  assert.strictEqual(rows("ps 118", "RESULT").length, 176)
})

test("book, chapter and verse", () => {
  assert.deepStrictEqual(rows("mat 4:23", "RESULT").map((r) => r[1]), ["Matthew 4:23"])
  assert.deepStrictEqual(rows("mat4:23", "RESULT").map((r) => r[1]), ["Matthew 4:23"])
  assert.deepStrictEqual(rows("1 cor 13:4", "RESULT").map((r) => r[1]), ["1 Corinthians 13:4"])
})

test("exact abbreviations still win", () => {
  assert.deepStrictEqual(rows("Jn 3:16", "RESULT").map((r) => r[1]), ["John 3:16"])
  assert.deepStrictEqual(rows("job", "NAV")[0].slice(1, 2), ["Job 1"])
})

test("roman-numeral aliases do not capture short prefixes", () => {
  assert.ok(rows("isa", "NAV").every((r) => r[1].startsWith("Isaiah")))
})

test("out-of-range chapter and verse explain the range", () => {
  assert.deepStrictEqual(rows("mat 40", "STATUS")[0], ["STATUS", "Matthew has 28 chapters"])
  assert.deepStrictEqual(rows("mat 4:99", "STATUS")[0], ["STATUS", "Matthew 4 has 25 verses"])
})

test("phrases still fall through to text search", () => {
  assert.strictEqual(rows("god so loved", "RESULT")[0][1], "John 3:16")
  assert.strictEqual(rows("god so loved", "NAV").length, 0)
})
