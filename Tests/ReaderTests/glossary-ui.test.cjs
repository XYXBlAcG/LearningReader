const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const root=path.resolve(__dirname,'../../Sources/LearningCore/Resources/Reader');
function setup(){
 const dom=new JSDOM('<main id="article"></main>',{runScripts:'outside-only',url:'https://offline.test/'});
 for(const file of ['vendor/marked.min.js','vendor/marked-cjk-friendly.min.js','vendor/purify.min.js','vendor/turndown-7.2.2.js','vendor/turndown-plugin-gfm-1.0.2.js','selection-copy.js','markdown.js','text-map.js','glossary-core.js','glossary-ui.js'])dom.window.eval(fs.readFileSync(path.join(root,file),'utf8'));
 return dom;
}
const library={version:1,terms:[{id:'mean-value',term:'中值定理',aliases:[],subject:'微积分',body:'## 直觉\n平均速度。\n\n## 定义\n闭区间连续。\n\n## 例子\n$f(x)=x^2$。',notes:[],related:[]}]};
test('marking crosses inline emphasis but not links, code, math or block boundaries',async()=>{
 const dom=setup();try{
 const w=dom.window,article=w.document.getElementById('article');
 article.innerHTML=w.ReaderMarkdown.render('中值**定理**与中值定理。\n\n`中值定理` [中值定理](x.md) $\\text{中值定理}$\n\n中值\n\n定理');
 const before=article.textContent;
 const view=await w.ReaderGlossaryUI.mount(article,{library,mode:'all'});
 assert.equal(article.querySelectorAll('.glossary-term').length,3);
 assert.equal(article.querySelectorAll('code .glossary-term,a .glossary-term,[data-math-source] .glossary-term').length,0);
 assert.equal(article.textContent,before);
 assert.ok(w.ReaderSelectionCopy.nodesMarkdown([article]).includes('中值**定理**'));
 view.dispose();assert.equal(article.querySelectorAll('.glossary-term').length,0);assert.equal(article.textContent,before);
 }finally{dom.window.close();}
});
test('first occurrence mode avoids repeated marks; popup stays outside copied article',async()=>{
 const dom=setup();try{
 const w=dom.window,article=w.document.getElementById('article');article.innerHTML='<p>中值定理，中值定理。</p>';
 const view=await w.ReaderGlossaryUI.mount(article,{library,mode:'once'});
 assert.equal(article.querySelectorAll('.glossary-term').length,1);
 await view.openTerm(['mean-value']);
 assert.ok(w.document.querySelector('.glossary-card').textContent.includes('平均速度'));
 assert.equal(article.querySelector('.glossary-card'),null);
 assert.equal(w.ReaderSelectionCopy.nodesMarkdown([article]),'中值定理，中值定理。');
 view.dispose();assert.equal(w.document.querySelector('.glossary-card'),null);
 }finally{dom.window.close();}
});
test('off mode preserves article and ambiguous words show choices',async()=>{
 const dom=setup();try{
 const w=dom.window,article=w.document.getElementById('article');article.innerHTML='<p>中值定理。</p>';
 const second={...library.terms[0],id:'cauchy',term:'柯西中值定理'};
 const view=await w.ReaderGlossaryUI.mount(article,{library:{version:1,terms:[...library.terms,second]},mode:'off'});
 assert.equal(article.querySelector('.glossary-term'),null);
 await view.openTerm(['mean-value','cauchy']);
 assert.equal(w.document.querySelectorAll('.glossary-choice').length,2);
 view.dispose();
 }finally{dom.window.close();}
});
test('nested excluded content cannot shift later term positions',async()=>{
 const dom=setup();try{
 const w=dom.window,article=w.document.getElementById('article');
 article.innerHTML='<h2><span>无关标题文字</span></h2><p><a href="x"><strong>链接文字</strong></a><span data-math-source="$x$"><i>公式文字</i></span>这是中值定理的例子。</p>';
 const view=await w.ReaderGlossaryUI.mount(article,{library,mode:'all'});
 assert.deepEqual([...article.querySelectorAll('.glossary-term')].map(n=>n.textContent),['中值定理']);
 view.dispose();
 }finally{dom.window.close();}
});
test('native presentation delegates term and library without web dialogs',async()=>{
 const dom=setup();try{
  const w=dom.window,article=w.document.getElementById('article');article.innerHTML='<p>中值定理</p>';
  let ids=null,opened=false;
  const view=await w.ReaderGlossaryUI.mount(article,{library,onPresent:value=>{ids=value},onPresentLibrary:()=>{opened=true}});
  await view.openTerm(['mean-value']);view.openLibrary();
  assert.deepEqual(Array.from(ids),['mean-value']);assert.equal(opened,true);
  assert.equal(w.document.querySelector('.glossary-card,.glossary-library'),null);view.dispose();
 }finally{dom.window.close()}
});
