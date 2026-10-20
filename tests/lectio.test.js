// Lectio Divina passages and Catena excerpts. Run with: node tests/lectio.test.js
const assert = require("assert")
const { execFileSync } = require("child_process")
const path = require("path")

const HELPER = path.join(__dirname, "..", "bin", "omarchy-catholic")

function lectio(reference) {
  return JSON.parse(execFileSync(HELPER, ["lectio", reference], { encoding: "utf8" }))
}

function test(name, fn) {
  try { fn(); console.log("ok - " + name) }
  catch (e) { console.error("FAIL - " + name); console.error(e); process.exitCode = 1 }
}

test("today's Gospel resolves with Catena excerpts", () => {
  const passage = lectio("Luke 12:35-38")
  assert.strictEqual(passage.reference, "Luke 12:35-38")
  assert.strictEqual(passage.verses.length, 4)
  assert.deepStrictEqual(passage.verses.map((v) => v[0]), [35, 36, 37, 38])
  assert.ok(passage.commentary.length > 0)
  assert.ok(passage.commentary.length <= 6)
  assert.match(passage.commentary[0][0], /\S/)
})

test("a non-Gospel passage has no Catena excerpts", () => {
  const passage = lectio("Ephesians 2:12-22")
  assert.strictEqual(passage.verses.length, 11)
  assert.deepStrictEqual(passage.commentary, [])
})

test("a trailing letter on a verse is accepted", () => {
  const passage = lectio("Matthew 5:1-12a")
  assert.strictEqual(passage.verses.length, 12)
  assert.strictEqual(passage.verses[passage.verses.length - 1][0], 12)
})

test("a whole chapter returns its verses", () => {
  const passage = lectio("Genesis 1")
  assert.strictEqual(passage.verses.length, 31)
  assert.strictEqual(passage.verses[0][0], 1)
})

test("an unrecognised reference reports an error", () => {
  const passage = lectio("not a reference")
  assert.match(passage.error, /Unrecognized Gospel reference/)
})
