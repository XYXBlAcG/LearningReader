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
