const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const reader=path.resolve(__dirname,'../../Sources/LearningCore/Resources/Reader');
const read=file=>fs.readFileSync(path.join(reader,file),'utf8');

test('reader and geometry reuse the same font source',()=>{
  assert.match(read('style.css'),/@import url\("\.\/typography\.css"\)/);
  assert.match(read('geometry/style.css'),/@import url\("\.\.\/typography\.css"\)/);
  assert.match(read('geometry/style.css'),/font-family:var\(--sans\)/);
  assert.match(read('geometry/app.js'),/fontFamily=getComputedStyle\(root\)\.fontFamily/);
  assert.match(read('geometry/app.js'),/family:fontFamily/);
  assert.match(read('typography.css'),/vendor\/fonts\/inter-400\.woff2/);
});

test('reader and geometry use one MathJax configuration',()=>{
  assert.match(read('index.html'),/src="\/reader\/math-config.js"/);
  assert.doesNotMatch(read('index.html'),/window\.MathJax\s*=/);
  assert.match(read('geometry/bootstrap.js'),/\.\.\/math-config.js/);
  assert.doesNotMatch(read('geometry/bootstrap.js'),/window\.MathJax\s*=/);
  assert.match(read('math-config.js'),/processEscapes:true/);
  assert.match(read('math-config.js'),/fontCache:'global'/);
});

test('reader and previews share Codex colors and range controls',()=>{
  assert.match(read('style.css'),/@import url\("\.\/theme\.css"\)/);
  const geometry=read('geometry/style.css');
  assert.match(geometry,/@import url\("\.\.\/theme\.css"\)/);
  assert.match(geometry,/--page:var\(--bg\)/);
  assert.match(geometry,/--text:var\(--ink\)/);
  assert.doesNotMatch(geometry,/prefers-color-scheme|accent-color:var\(--blue\)/);
  const theme=read('theme.css');
  assert.match(theme,/color-scheme:\s*light/);
  assert.match(theme,/input\[type=range\]::-webkit-slider-runnable-track/);
  assert.match(theme,/input\[type=range\]::-webkit-slider-thumb/);
  assert.match(theme,/input\[type=range\]::-moz-range-thumb/);
  assert.match(theme,/input\[type=range\]:focus-visible/);
  assert.match(theme,/background:\s*var\(--accent\)/);
});
