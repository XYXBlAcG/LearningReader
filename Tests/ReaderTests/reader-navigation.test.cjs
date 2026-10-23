const test = require("node:test");
const assert = require("node:assert/strict");
const { ReaderNavigation } = require("../../Sources/LearningCore/Resources/Reader/navigation.js");

function environment() {
  const data = new Map();
  const storage = { getItem: key => data.get(key) ?? null, setItem: (key, value) => data.set(key, value), removeItem: key => data.delete(key) };
  const entries = [{ state: null, url: "/reader" }];
  let cursor = 0;
  const browser = {
    get state() { return entries[cursor].state; },
    replaceState(state, _, url) { entries[cursor] = { state, url }; },
    pushState(state, _, url) { entries.splice(cursor + 1); entries.push({ state, url }); cursor++; },
    go(delta) { cursor += delta; },
  };
  return { storage, browser, entries };
}

test("back chain preserves distinct positions for repeated visits", () => {
  const env = environment();
  const nav = new ReaderNavigation(env.browser, env.storage, env.storage);
  const a = { kind: "note", path: "微积分/a.md", anchor: "" };
  nav.visit(a, { top: 100, references: ["参考答案"] });
  nav.checkpoint({ top: 480, references: ["参考答案"] });
  nav.visit({ kind: "note", path: "微积分/b.md", anchor: "定义" }, { top: 20 });
  nav.visit(a, { top: 5 });
  assert.equal(env.entries[0].state.reader.snapshot.top, 480);
  assert.equal(env.entries[2].state.reader.snapshot.top, 5);
  assert.equal(nav.records.length, 2);
  assert.equal(nav.canBack, true);
});

test("a new visit after going back discards the forward branch", () => {
  const env = environment();
  const nav = new ReaderNavigation(env.browser, env.storage, env.storage);
  for (const path of ["a.md", "b.md", "c.md"]) nav.visit({ kind: "note", path }, { top: 0 });
  env.browser.go(-1);
  nav.adopt(env.browser.state);
  assert.equal(nav.canForward, true);
  nav.visit({ kind: "note", path: "d.md" }, { top: 0 });
  assert.equal(nav.canForward, false);
  assert.equal(env.entries.length, 3);
});

test("same-document anchors remain separate visits, exact repeats do not", () => {
  const env = environment();
  const nav = new ReaderNavigation(env.browser, env.storage, env.storage);
  nav.visit({ kind: "note", path: "a.md", anchor: "" }, { top: 40 });
  nav.visit({ kind: "note", path: "a.md", anchor: "定义" }, { top: 80 });
  nav.visit({ kind: "note", path: "a.md", anchor: "定义" }, { top: 90 });
  assert.equal(env.entries.length, 2);
  assert.equal(nav.records.length, 1);
});

test("recent records persist with snapshots and are bounded to 200", () => {
  const env = environment();
  const nav = new ReaderNavigation(env.browser, env.storage, env.storage);
  for (let i = 0; i < 205; i++) nav.visit({ kind: "exercise", path: i + ".md" }, { top: i });
  const restored = new ReaderNavigation(env.browser, env.storage, env.storage);
  assert.equal(restored.records.length, 200);
  assert.equal(restored.records[0].snapshot.top, 204);
  restored.clear();
  assert.deepEqual(restored.records, []);
  assert.equal(restored.canBack, true);
});

test("reloading the current entry keeps an existing forward branch", () => {
  const env = environment();
  const nav = new ReaderNavigation(env.browser, env.storage, env.storage);
  const a = { kind: 'note', path: 'a.md' };
  nav.visit(a, { top: 1 });
  nav.visit({ kind: 'note', path: 'b.md' }, { top: 2 });
  env.browser.go(-1);nav.adopt(env.browser.state);
  nav.visit(a, { top: 3 });
  assert.equal(nav.canForward, true);
  assert.equal(env.entries.length, 2);
});
