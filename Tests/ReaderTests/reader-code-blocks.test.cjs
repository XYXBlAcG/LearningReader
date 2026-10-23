const test = require("node:test");
const assert = require("node:assert/strict");
const { copyText, languageLabel } = require("../../Sources/LearningCore/Resources/Reader/code-blocks.js");

test("maps fenced C++ aliases to one label", () => {
  assert.equal(languageLabel("cpp"), "C++");
  assert.equal(languageLabel("c++"), "C++");
});

test("uses readable labels for common course languages", () => {
  assert.equal(languageLabel("python"), "Python");
  assert.equal(languageLabel("plaintext"), "文本");
  assert.equal(languageLabel(""), "代码");
});

test("keeps an unknown language visible", () => {
  assert.equal(languageLabel("julia"), "JULIA");
});

test("copies the code source without changing whitespace or symbols", async () => {
  let copied = "";
  const source = "vector<vector<double>> a;\n  abs(x) < EPS;\n";
  await copyText(source, { writeText: async (text) => { copied = text; } });
  assert.equal(copied, source);
});
