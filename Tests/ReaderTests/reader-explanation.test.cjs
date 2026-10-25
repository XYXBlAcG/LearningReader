const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const root = path.resolve(__dirname, '../../Sources/LearningCore/Resources/Reader');

function page(html) {
  const dom = new JSDOM(html, {runScripts:'outside-only', url:'https://example.org/read'});
  for (const file of ['vendor/turndown-7.2.2.js','vendor/turndown-plugin-gfm-1.0.2.js','selection-copy.js','explanation.js']) dom.window.eval(fs.readFileSync(path.join(root,file),'utf8'));
  const range = dom.window.document.createRange();
  range.selectNodeContents(dom.window.document.getElementById('selected'));
  dom.window.getSelection().addRange(range);
  return dom;
}

test('course context contains exact complete original Markdown, including closed answers and file end', () => {
  const dom = page('<main id="article"><p id="selected">求极限</p><details><summary>参考答案</summary>完整证明</details></main>');
  try {
    const source = '# 首段\n\n' + '上下文。'.repeat(4000) + '\n\n## 参考答案\n完整证明\n\n末尾原文';
    const current = {kind:'exercise',path:'练习/a.md',source};
    const value = dom.window.ReaderExplanation.course(current, dom.window.document.getElementById('article'), '题目');
    assert.equal(value.text,'求极限');
    assert.equal(value.document,source);
    assert.equal(value.identity,'exercise:练习/a.md');
    assert.equal(dom.window.ReaderExplanation.identity(current,null),'');
    dom.window.document.getElementById('article').setAttribute('aria-busy','true');
    assert.equal(dom.window.ReaderExplanation.course(current,dom.window.document.getElementById('article'),'题目'),null);
  } finally { dom.window.close(); }
});

test('bridge document identity and material change together on navigation', () => {
  const dom = page('<main id="article"><p id="selected">问题</p></main>');
  try {
    dom.window.eval(fs.readFileSync(path.join(root,'host-bridge.js'),'utf8'));
    let current = {kind:'note',path:'a.md',source:'第一篇完整文件'};
    const article = dom.window.document.getElementById('article');
    const bridge = dom.window.ReaderHostBridge.createBridge({
      identity:() => dom.window.ReaderExplanation.identity(current,article),
      material:() => dom.window.ReaderExplanation.course(current,article,'文档'),
    },() => {});
    assert.equal(bridge.material().document,'第一篇完整文件');
    assert.equal(bridge.identity(),'note:a.md');
    current = {kind:'exercise',path:'b.md',source:'第二篇完整文件'};
    assert.equal(bridge.identity(),'exercise:b.md');
    assert.equal(bridge.material().identity,bridge.identity());
    assert.equal(bridge.material().document,'第二篇完整文件');
  } finally { dom.window.close(); }
});

test('web context includes whole document and formula sources, excluding executable and form data', () => {
  const dom = page('<h1>开头</h1><p id="selected">问题</p><div><span data-math-source="$x^2$"><svg>排版</svg></span></div><p>末尾条件</p><script>privateScript()</script><textarea>私密输入</textarea><iframe src="https://other.example/"></iframe>');
  try {
    const value = dom.window.ReaderExplanation.webpage(dom.window.document);
    assert.equal(value.text,'问题');
    assert.ok(value.document.includes('开头'));
    assert.ok(value.document.includes('末尾条件'));
    assert.ok(value.document.includes('$x^2$'));
    assert.equal(value.document.includes('privateScript'),false);
    assert.equal(value.document.includes('私密输入'),false);
    assert.equal(value.identity,'https://example.org/read');
  } finally { dom.window.close(); }
});
