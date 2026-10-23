const test = require("node:test");
const assert = require("node:assert/strict");
const {
  documentKey,
  parsePinned,
  togglePinned,
  resolvePinned,
} = require("../../Sources/LearningCore/Resources/Reader/pinned-files.js");

test("parses valid unique pinned document keys", () => {
  assert.deepEqual(
    parsePinned('["note:专题/02-泰勒展开.md","note:专题/02-泰勒展开.md","invalid"]'),
    ["note:专题/02-泰勒展开.md"],
  );
  assert.deepEqual(parsePinned("not json"), []);
});

test("toggles a pinned document with newest items first", () => {
  const key = documentKey("note", "专题/02-泰勒展开.md");
  assert.deepEqual(togglePinned([], key), [key]);
  assert.deepEqual(togglePinned(["exercise:专题/02-泰勒展开.md"], key), [
    key,
    "exercise:专题/02-泰勒展开.md",
  ]);
  assert.deepEqual(togglePinned([key], key), []);
});

test("resolves pinned documents in saved order and removes stale paths", () => {
  const files = {
    notes: [{ path: "专题/02-泰勒展开.md", label: "专题/02-泰勒展开" }],
    exercises: [{ path: "专题/02-泰勒展开.md", label: "专题/02-泰勒展开" }],
  };
  assert.deepEqual(resolvePinned([
    "exercise:专题/02-泰勒展开.md",
    "note:已删除.md",
    "note:专题/02-泰勒展开.md",
  ], files), [
    { kind: "exercise", file: files.exercises[0] },
    { kind: "note", file: files.notes[0] },
  ]);
});
