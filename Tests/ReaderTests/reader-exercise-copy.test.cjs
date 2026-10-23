const test = require("node:test");
const assert = require("node:assert/strict");

const modulePath = "../../Sources/LearningCore/Resources/Reader/exercise-copy.js";

function node(tagName, textContent = "", children = []) {
  return { tagName, textContent, children };
}

function list(...items) {
  return node("OL", "", items.map((text) => node("LI", text)));
}

test("groups a split question with its following LaTeX blocks", () => {
  const { questionRanges, questionSource } = require(modulePath);
  const children = [
    node("H2", "题目"),
    list("求极限"),
    node("P", "$$\\lim_{x\\to0}f(x)$$"),
    node("P", "并说明理由。"),
    list("第二题"),
    node("H2", "参考答案"),
  ];
  const ranges = questionRanges(children);
  assert.equal(ranges.length, 2);
  assert.equal(questionSource(children, ranges[0]), "求极限\n\n$$\\lim_{x\\to0}f(x)$$\n\n并说明理由。");
});

test("creates one range per item in a compact ordered list", () => {
  const { questionRanges } = require(modulePath);
  const children = [list("题一", "题二", "题三"), node("H2", "参考答案")];
  const ranges = questionRanges(children);
  assert.deepEqual(ranges.map((range) => range.itemIndex), [0, 1, 2]);
});

test("attaches blocks after a compact list to its final question", () => {
  const { questionRanges, questionSource } = require(modulePath);
  const children = [
    list("第三十四题", "第三十五题"),
    node("P", "(1) 第一小问"),
    node("P", "(2) 第二小问"),
    list("第三十六题"),
    node("H2", "参考答案"),
  ];
  const ranges = questionRanges(children);
  assert.equal(questionSource(children, ranges[0]), "第三十四题");
  assert.equal(questionSource(children, ranges[1]), "第三十五题\n\n(1) 第一小问\n\n(2) 第二小问");
});

test("never treats reference answers or an index page as questions", () => {
  const { questionRanges } = require(modulePath);
  assert.equal(questionRanges([node("H2", "章节索引"), list("第一章")]).length, 0);
  assert.equal(questionRanges([list("题目"), node("H2", "参考答案"), list("解题步骤")]).length, 1);
});

test("copies the preserved question source unchanged", async () => {
  const { copyText } = require(modulePath);
  let copied = "";
  const source = "设 $A=\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}$。";
  await copyText(source, { writeText: async (value) => { copied = value; } });
  assert.equal(copied, source);
});

test("numbered headings include the complete statement but not the next question or answers", () => {
  const { questionRanges, questionSource } = require(modulePath);
  const children = [
    node("H2", "知识点导航"), node("P", "复习入口"),
    node("H2", "题目"), node("H3", "7."), node("P", "求曲面方程。"),
    node("P", "$$\\frac{x^2}{4}-z^2=0$$"),
    node("H3", "29(1)."), node("P", "证明投影范围。"),
    node("H2", "参考答案"), node("H3", "7."), node("P", "解答"),
  ];
  const ranges = questionRanges(children);
  assert.equal(ranges.length, 2);
  assert.equal(questionSource(children, ranges[0]), "7.\n\n求曲面方程。\n\n$$\\frac{x^2}{4}-z^2=0$$");
  assert.equal(questionSource(children, ranges[1]), "29(1).\n\n证明投影范围。");
});

test("subquestion lists inside a heading question do not create extra copy buttons", () => {
  const { questionRanges, questionSource } = require(modulePath);
  const children = [node("H3", "1"), node("P", "分别计算"), list("小问一", "小问二"), node("H2", "参考答案")];
  const ranges = questionRanges(children);
  assert.equal(ranges.length, 1);
  assert.equal(questionSource(children, ranges[0]), "1\n\n分别计算\n\n小问一\n小问二");
});

test("Chinese question numbers and titled numeric question headings use the same ranges", () => {
  const { questionRanges } = require(modulePath);
  assert.equal(questionRanges([node('H3','第 1 题'),node('P','题干'),node('H3','2. 空间投影'),node('P','题干'),node('H2','参考答案')]).length,2);
});

test("formats lettered and numbered subquestions without touching formulas", () => {
  const { formatSubquestions } = require(modulePath);
  const source = [
    "1. (a) 求 $f(1+x)$；(b) 证明结论。",
    "   (1) 计算第一项。",
    "   (2) 计算第二项。",
  ].join("\n");
  const result = formatSubquestions(source);
  assert.match(result, /^1\. <span class="subquestion-label">\(a\)<\/span> 求 \$f\(1\+x\)\$/);
  assert.match(result, /<br class="subquestion-break"><span class="subquestion-label">\(b\)<\/span> 证明结论/);
  assert.match(result, /<br class="subquestion-break"><span class="subquestion-label">\(1\)<\/span> 计算第一项/);
  assert.match(result, /<br class="subquestion-break"><span class="subquestion-label">\(2\)<\/span> 计算第二项/);
  assert.match(result, /\$f\(1\+x\)\$/);
});
