const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),{JSDOM}=require('jsdom');
test('quote locator ignores code and ambiguous matches and preserves original content',()=>{
 const dom=new JSDOM('<article><h2>标题</h2><p>前文需要解释的文字后文</p><pre>需要解释的文字</pre><p>重复 重复</p></article>',{runScripts:'outside-only'});
 try {
  const w=dom.window;w.eval(fs.readFileSync('Sources/LearningCore/Resources/Reader/text-map.js','utf8'));w.eval(fs.readFileSync('Sources/LearningCore/Resources/Reader/annotations.js','utf8'));
  const article=w.document.querySelector('article'),before=article.innerHTML;
  assert.equal(w.ReaderAnnotations.locate(article,'需要解释的文字').toString(),'需要解释的文字');
  assert.equal(w.ReaderAnnotations.locate(article,'重复'),null);
  assert.equal(article.innerHTML,before);
 }finally{dom.window.close()}
});
test('reader entry points load the text map before annotation and glossary consumers',()=>{
 const directory='Sources/LearningCore/Resources/Reader/';
 for(const file of ['index.html','ai-answer.html']){
  const dom=new JSDOM(fs.readFileSync(directory+file,'utf8'));
  try {
   const scripts=[...dom.window.document.scripts].map(s=>s.getAttribute('src')?.split('/').at(-1));
   assert.ok(scripts.includes('text-map.js'));
   assert.ok(scripts.indexOf('text-map.js')<scripts.indexOf('glossary-ui.js'));
   if(file==='index.html')assert.ok(scripts.indexOf('annotations.js')>=0&&scripts.indexOf('annotations.js')<scripts.indexOf('app.js'));
  }finally{dom.window.close()}
 }
});
test('quote locator spans paragraphs and inline formatting with Unicode offsets',()=>{
 const dom=new JSDOM('<article><p>😀第一段<strong>连续函数</strong></p><p>第二段内容。</p></article>',{runScripts:'outside-only'});
 try{const w=dom.window;for(const file of ['text-map.js','annotations.js'])w.eval(fs.readFileSync('Sources/LearningCore/Resources/Reader/'+file,'utf8'));const range=w.ReaderAnnotations.locate(w.document.querySelector('article'),'第一段连续函数 第二段内容。');assert.ok(range);assert.equal(range.toString(),'第一段连续函数第二段内容。')}finally{dom.window.close()}
});
test('context disambiguates repeated words and invalid context never chooses another occurrence',()=>{
 const dom=new JSDOM('<article><p>甲连续函数后文</p><p>乙连续函数结尾</p></article>',{runScripts:'outside-only'});
 try{const w=dom.window;for(const f of ['text-map.js','annotations.js'])w.eval(fs.readFileSync('Sources/LearningCore/Resources/Reader/'+f,'utf8'));const a=w.document.querySelector('article');assert.equal(w.ReaderAnnotations.locate(a,'连续函数','乙','结尾').startContainer.parentElement.textContent,'乙连续函数结尾');assert.equal(w.ReaderAnnotations.locate(a,'连续函数','丙','结尾'),null)}finally{dom.window.close()}
});
test('colored marks are grouped and cleaned without mutating the course document',()=>{
 const dom=new JSDOM('<article><p>需要解释的文字与新的笔记。</p></article>',{runScripts:'outside-only'});
 try{
  const w=dom.window;for(const f of ['text-map.js','annotations.js'])w.eval(fs.readFileSync('Sources/LearningCore/Resources/Reader/'+f,'utf8'));
  w.CSS={highlights:new Map()};w.Highlight=class{constructor(...ranges){this.ranges=ranges}};w.ReaderMarkdown={render:text=>text};
  const article=w.document.querySelector('article'),before=article.innerHTML;
  const missing=w.ReaderAnnotations.mount(article,[{id:'a',quote:'需要解释的文字',color:'#123456'},{id:'b',quote:'新的笔记',color:'#ABCDEF',underline:'true'},{id:'c',quote:'不在原文'}],()=>{});
  assert.deepEqual(Array.from(missing),['c']);assert.equal(w.CSS.highlights.size,2);assert.match(w.document.getElementById('annotation-colors').textContent,/#12345655/);assert.equal(article.innerHTML,before);
  w.ReaderAnnotations.mount(article,[],()=>{});assert.equal(w.CSS.highlights.size,0);
 }finally{dom.window.close()}
});
