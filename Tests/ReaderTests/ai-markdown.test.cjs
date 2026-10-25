const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const root = path.resolve(__dirname, '../../Sources/LearningCore/Resources/Reader');

async function reader() {
  const dom = new JSDOM('<main id="article"></main>', { runScripts: 'outside-only', url: 'https://offline.test/' });
  for (const file of ['vendor/marked.min.js', 'vendor/marked-cjk-friendly.min.js', 'vendor/purify.min.js', 'vendor/turndown-7.2.2.js', 'vendor/turndown-plugin-gfm-1.0.2.js', 'selection-copy.js', 'markdown.js', 'math-config.js', 'vendor/mathjax/tex-svg.js']) {
    dom.window.eval(fs.readFileSync(path.join(root, file), 'utf8'));
  }
  await dom.window.MathJax.startup.promise;
  return dom;
}

test('shared renderer typesets fractions, matrices, cases and aligned proofs with original LaTeX', async () => {
  const dom = await reader();
  try {
    const w = dom.window;
    const source = String.raw`直觉：$\frac{1}{2}$ 是一半。

## 严谨过程

$$
\begin{pmatrix}1 & 2 \\ 3 & 4\end{pmatrix}
$$

$$
f(x)=\begin{cases}x^2 & x\ge0 \\ -x & x<0\end{cases}
$$

$$
\begin{aligned}a&=\frac{b}{c}\\ac&=b\end{aligned}
$$

\(x+1\) 与 \[x^2\]

~~~python
cost = "$x$"
~~~`;
    const article = w.document.getElementById('article');
    article.innerHTML = w.ReaderMarkdown.render(source);
    await w.MathJax.typesetPromise([article]);
    assert.equal(article.querySelectorAll('mjx-container').length, 6);
    assert.equal(article.querySelectorAll('[data-mjx-error], mjx-merror, [data-mml-node="merror"]').length, 0);
    assert.equal(article.querySelector('pre code').textContent.trim(), 'cost = "$x$"');
    assert.equal(article.querySelector('pre .math-source'), null);
    assert.ok(article.querySelector('[data-math-source]').dataset.mathSource.includes('\\frac{1}{2}'));
  } finally { dom.window.close(); }
});

test('selection preserves mathematical source after typesetting', async () => {
  const dom = await reader();
  try {
    const w = dom.window, article = w.document.getElementById('article');
    article.innerHTML = w.ReaderMarkdown.render(String.raw`求 $\frac{x}{2}$ 的值。`);
    await w.MathJax.typesetPromise([article]);
    const range = w.document.createRange(); range.selectNodeContents(article);
    w.getSelection().addRange(range);
    assert.match(w.ReaderSelectionCopy.selectionMarkdown(article), /\$\\frac\{x\}\{2\}\$/);
  } finally { dom.window.close(); }
});

test('partial streaming formulas recover when closed and returned HTML cannot execute scripts', async () => {
  const dom = await reader();
  try {
    const w = dom.window, article = w.document.getElementById('article');
    const chunks = ['直觉\n\n$$\n\\frac{', '1}{2}\n$$\n\n<script>window.pwned=true</script><img src=x onerror="window.pwned=true"><iframe src="https://example.org"></iframe>'];
    let source = '';
    for (const chunk of chunks) {
      source += chunk;
      w.MathJax.typesetClear([article]);
      article.innerHTML = w.ReaderMarkdown.render(source);
      await w.MathJax.typesetPromise([article]);
    }
    assert.equal(article.querySelectorAll('mjx-container').length, 1);
    assert.equal(article.querySelectorAll('script,iframe,[onerror]').length, 0);
    assert.equal(w.pwned, undefined);
  } finally { dom.window.close(); }
});

test('answer streaming host coalesces updates and replaces old MathJax items', async () => {
  const dom = await reader();
  try {
    const w = dom.window;
    w.scrollTo = () => {};
    for (const file of ['code-blocks.js', 'ai-answer.js']) w.eval(fs.readFileSync(path.join(root, file), 'utf8'));
    const first = w.AIAnswer.update('直觉：$\\frac{');
    await w.AIAnswer.update('直觉：$\\frac{1}{2}$。\n\n严谨过程：$x=1$。');
    await first;
    const article = w.document.getElementById('article');
    assert.equal(article.querySelectorAll('mjx-container').length, 2);
    assert.equal([...w.MathJax.startup.document.math].length, 2);
    const range = w.document.createRange(); range.selectNodeContents(article);
    w.getSelection().addRange(range);
    assert.match(w.ReaderSelectionCopy.selectionMarkdown(article), /\\frac\{1\}\{2\}/);
  } finally { dom.window.close(); }
});

test('Chinese punctuation and math inside strong text share correct emphasis parsing', async () => {
  const dom = await reader();
  try {
    const w = dom.window, article = w.document.getElementById('article');
    for (const source of ['这是**“重点”**内容', '这是**重点：**内容', String.raw`这是**$\frac{1}{2}$**的意义`, String.raw`这是**公式 $x+1$**的意义`]) {
      w.MathJax.typesetClear([article]);
      article.innerHTML = w.ReaderMarkdown.render(source);
      await w.MathJax.typesetPromise([article]);
      assert.equal(article.querySelectorAll('strong').length, 1, source);
      assert.equal(article.textContent.includes('**'), false, source);
      if (source.includes('$')) assert.equal(article.querySelectorAll('strong mjx-container').length, 1, source);
    }
    article.innerHTML = w.ReaderMarkdown.render('**直觉与 *理由***，\\*\\*原样\\*\\*，`**代码**`');
    assert.equal(article.querySelectorAll('strong em').length, 1);
    assert.equal(article.querySelector('code').textContent, '**代码**');
    assert.ok(article.textContent.includes('**原样**'));
  } finally { dom.window.close(); }
});

test('streamed strong punctuation renders when the closing delimiter arrives', async () => {
  const dom = await reader();
  try {
    const w = dom.window, article = w.document.getElementById('article');
    article.innerHTML = w.ReaderMarkdown.render('这是**“重点”');
    assert.equal(article.querySelector('strong'), null);
    article.innerHTML = w.ReaderMarkdown.render('这是**“重点”**内容');
    assert.equal(article.querySelector('strong').textContent, '“重点”');
  } finally { dom.window.close(); }
});
