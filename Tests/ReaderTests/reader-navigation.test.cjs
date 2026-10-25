const test = require("node:test");
const assert = require("node:assert/strict");
const { ReaderNavigation } = require("../../Sources/LearningCore/Resources/Reader/navigation.js");

test('history deletion, clear and undo persist without resurrecting on passive restore', () => {
  const env = environment();
  const nav = new ReaderNavigation(env.browser,env.storage,env.storage);
  nav.visit({kind:'note',path:'a.md'},{top:10});
  nav.visit({kind:'note',path:'b.md'},{top:20});
  nav.remove('note','a.md');
  assert.deepEqual(nav.records.map(x=>x.path),['b.md']);
  nav.clear();
  assert.equal(nav.records.length,0);
  nav.undo();
  assert.deepEqual(nav.records.map(x=>x.path),['b.md']);
  nav.clear();
  const restored = new ReaderNavigation(env.browser,env.storage,env.storage);
  restored.visit({kind:'note',path:'b.md'},{top:20},{remember:false});
  restored.checkpoint({top:40});
  assert.equal(restored.records.length,0);
  restored.visit({kind:'note',path:'b.md'},{top:40});
  assert.equal(restored.records.length,1);
});

function environment(initialURL = "mathreader://local/reader/index.html") {
  const data = new Map();
  const storage = { getItem: key => data.get(key) ?? null, setItem: (key, value) => data.set(key, value), removeItem: key => data.delete(key) };
  const entries = [{ state: null, url: initialURL }];
  let cursor = 0;
  const browser = {
    get state() { return entries[cursor].state; },
    get url() { return entries[cursor].url; },
    replaceState(state, _, url) { entries[cursor] = { state, url: new URL(url, entries[cursor].url).href }; },
    pushState(state, _, url) { entries.splice(cursor + 1); entries.push({ state, url: new URL(url, entries[cursor].url).href }); cursor++; },
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

for (const page of ["mathreader://local/reader/index.html", "https://courses.example/reader/index.html", "http://127.0.0.1:8000/reader"]) {
  test("document visits and history keep the loaded reader page: " + page, () => {
    const env = environment(page);
    const nav = new ReaderNavigation(env.browser, env.storage, env.storage);
    const origin = new URL(page);
    const paths = ["数学笔记/第一课.md", "数学笔记/第二课 % #.md", "数学练习/第三课.md"];
    for (const [index, path] of paths.entries()) {
      const kind = index === 2 ? "exercise" : "note";
      nav.visit({ kind, path, anchor: "定义" }, { top: index });
      nav.checkpoint({ top: index + 1 });
      const current = new URL(env.browser.url);
      assert.equal(current.pathname, origin.pathname);
      assert.equal(current.protocol, origin.protocol);
      assert.equal(current.host, origin.host);
      assert.equal(current.searchParams.get("path"), path);
      assert.equal(current.searchParams.get("kind"), kind);
      assert.equal(current.searchParams.get("anchor"), "定义");
    }
    env.browser.go(-1);
    nav.adopt(env.browser.state);
    nav.checkpoint({ top: 42 });
    assert.equal(new URL(env.browser.url).pathname, origin.pathname);
    const restored = new ReaderNavigation(env.browser, env.storage, env.storage);
    assert.equal(restored.current.path, paths[1]);
    assert.equal(restored.canForward, true);
  });
}
