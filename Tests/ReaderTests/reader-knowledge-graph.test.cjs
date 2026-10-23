const test = require("node:test");
const assert = require("node:assert/strict");
const {
  renderWikiLinks,
  selectNeighborhood,
} = require("../../Sources/LearningCore/Resources/Reader/knowledge-graph.js");

test("renders wiki links as safe local markdown links", () => {
  assert.equal(
    renderWikiLinks("先看 [[09-微分#中值定理|拉格朗日中值定理]]。"),
    '先看 <a class="wiki-link" href="09-%E5%BE%AE%E5%88%86.md#%E4%B8%AD%E5%80%BC%E5%AE%9A%E7%90%86">拉格朗日中值定理</a>。',
  );
});

test("escapes wiki link labels", () => {
  assert.equal(
    renderWikiLinks("[[A|<img src=x>]]"),
    '<a class="wiki-link" href="A.md">&lt;img src=x&gt;</a>',
  );
});

test("does not transform wiki syntax shown as code", () => {
  const source = "```markdown\n[[A]]\n```\n正文 `[[B]]` 与 [[C]]";
  assert.equal(
    renderWikiLinks(source),
    '```markdown\n[[A]]\n```\n正文 `[[B]]` 与 <a class="wiki-link" href="C.md">C</a>',
  );
});

test("selects the active document and its one-hop linked concepts", () => {
  const graph = {
    nodes: [
      { id: "note:A.md", kind: "note", path: "A.md" },
      { id: "note:B.md#定义", kind: "note", path: "B.md", anchor: "定义" },
      { id: "note:C.md", kind: "note", path: "C.md" },
    ],
    edges: [
      { source: "note:A.md", target: "note:B.md#定义", type: "related" },
      { source: "note:C.md", target: "note:A.md", type: "prerequisite" },
    ],
  };

  const local = selectNeighborhood(graph, "note", "A.md");

  assert.deepEqual(local.nodes.map((node) => node.id).sort(), [
    "note:A.md",
    "note:B.md#定义",
    "note:C.md",
  ]);
  assert.equal(local.edges.length, 2);
});

test("matches an anchored node when its document is active", () => {
  const graph = {
    nodes: [{ id: "note:A.md#定义", kind: "note", path: "A.md", anchor: "定义" }],
    edges: [],
  };

  assert.equal(selectNeighborhood(graph, "note", "A.md").nodes[0].active, true);
});
