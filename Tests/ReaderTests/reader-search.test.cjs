const test = require("node:test");
const assert = require("node:assert/strict");
const { searchSections } = require("../../Sources/LearningCore/Resources/Reader/search.js");

const sections = [
  {
    kind: "exercise",
    path: "线性代数/练习.md",
    documentLabel: "伴随矩阵练习",
    heading: "参考答案",
    anchor: "参考答案",
    text: "这里需要计算代数余子式。",
  },
  {
    kind: "note",
    path: "线性代数/矩阵.md",
    documentLabel: "伴随矩阵",
    heading: "2. 代数余子式回顾",
    anchor: "2-代数余子式回顾",
    text: "删去一行一列后得到余子式，再添加符号。",
  },
  {
    kind: "note",
    path: "线性代数/行列式.md",
    documentLabel: "行列式",
    heading: "按行展开",
    anchor: "按行展开",
    text: "代数余子式带有棋盘符号。",
  },
];

test("ranks an exact concept heading above body-only matches", () => {
  const results = searchSections(sections, "代数余子式");

  assert.equal(results[0].path, "线性代数/矩阵.md");
  assert.equal(results[0].anchor, "2-代数余子式回顾");
  assert.match(results[0].snippet, /余子式/);
});

test("supports multiple whitespace-separated keywords", () => {
  const results = searchSections(sections, "代数 符号");

  assert.equal(results.length, 2);
  assert.equal(results[0].kind, "note");
});

test("returns no results when every keyword is absent", () => {
  assert.deepEqual(searchSections(sections, "特征 多项式"), []);
});
