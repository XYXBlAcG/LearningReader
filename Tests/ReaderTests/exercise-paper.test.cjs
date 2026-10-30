const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const root=path.resolve(__dirname,'../../Sources/LearningCore/Resources/Reader');
function paper(){
 const dom=new JSDOM('<main id="article"></main>',{runScripts:'outside-only'});
 for(const file of ['vendor/marked.min.js','vendor/marked-cjk-friendly.min.js','vendor/purify.min.js','vendor/turndown-7.2.2.js','vendor/turndown-plugin-gfm-1.0.2.js','selection-copy.js','markdown.js','exercise-copy.js','study-questions.js','exercise-paper.js'])dom.window.eval(fs.readFileSync(path.join(root,file),'utf8'));
 return dom;
}
test('paper keeps instructions, original numbering and formulas while moving reference sections after questions',async()=>{
 const dom=paper();try{
 const source='# 随堂练习\n\n请写出过程。\n\n## 微积分\n\n7. 求 $x^2$\n8. 求极限\n\n## 参考答案\n\n7. 秘密答案A\n8. 秘密答案B\n\n## 补充题\n\n9. 补充条件\n\n## 参考解析\n\n9. 秘密答案C';
 const result=await dom.window.ReaderPaper.prepare(source,{title:'练习',answers:false,space:'medium'},()=>null);
 const article=dom.window.document.getElementById('article');article.innerHTML=result.html;
 assert.match(article.textContent,/请写出过程/);assert.match(article.textContent,/补充条件/);assert.doesNotMatch(article.textContent,/秘密答案/);
 assert.equal(result.questionCount,3);assert.equal(article.querySelector('ol').start,7);assert.equal(article.querySelectorAll('.paper-question[data-space]').length,3);assert.ok([...article.querySelectorAll('.paper-tail')].every(n=>n.firstChild!==n.lastChild));assert.match(result.html,/x\^2/);
 const full=await dom.window.ReaderPaper.prepare(source,{title:'练习',answers:true,space:'none'},()=>null);
 article.innerHTML=full.html;assert.match(article.querySelector('.paper-answers').textContent,/秘密答案C/);assert.equal(article.querySelectorAll('.paper-question[data-space]').length,0);assert.equal(full.warnings.length,0);
 }finally{dom.window.close();}
});
test('paper reports ambiguous boundaries and does not delete unrelated reference material',async()=>{
 const dom=paper();try{
 const result=await dom.window.ReaderPaper.prepare('# 题目\n\n1. 条件\n\n## 参考资料\n\n必须阅读',{answers:false},()=>null);
 assert.match(result.html,/必须阅读/);assert.ok(result.warnings.length>0);
 }finally{dom.window.close();}
});
test('paper prepares only included images and rejects missing resources',async()=>{
 const dom=paper();try{
 const w=dom.window;let calls=[];w.fetch=async url=>{calls.push(url);return {ok:true,blob:async()=>new w.Blob(['image'],{type:'image/png'})};};
 const source='# 图题\n\n1. ![题图](figure.png)\n\n## 参考答案\n\n1. ![答案图](answer.png)';
 const result=await w.ReaderPaper.prepare(source,{answers:false},src=>'/media/'+src);
 assert.deepEqual(calls,['/media/figure.png']);assert.match(result.html,/data:image\/png;base64,/);
 w.fetch=async()=>({ok:false,status:404});await assert.rejects(w.ReaderPaper.prepare(source,{answers:false},src=>src),/题图|figure.png/);
 }finally{dom.window.close();}
});
test('paper export is derived and leaves the reading document untouched',async()=>{
 const dom=paper();try{
 const article=dom.window.document.getElementById('article');article.innerHTML='<p>当前阅读和位置</p>';const before=article.innerHTML;
 await dom.window.ReaderPaper.prepare('1. 题目\n\n## 参考答案\n\n1. 答案',{answers:false},()=>null);
 assert.equal(article.innerHTML,before);
 }finally{dom.window.close();}
});

test('compact lists and titled questions retain all nested statements exactly once',async()=>{
 const dom=paper();try{
 const result=await dom.window.ReaderPaper.prepare('# 试题\n\n### 第 7 题\n\n条件甲\n\n#### 小问\n\n条件乙\n\n### 第 8 题\n\n条件丙\n\n## 参考解答\n\n### 第 7 题\n\n答案甲',{answers:false,space:'large'},()=>null);
 assert.equal(result.questionCount,2);assert.match(result.html,/条件乙/);assert.doesNotMatch(result.html,/答案甲/);assert.equal(result.html.match(/条件乙/g).length,1);
 }finally{dom.window.close();}
});

test('answer appendix retains subject headings for repeated question numbers',async()=>{
 const dom=paper();try{
 const source='## 微积分\n\n### 题目\n\n1. 甲题\n\n### 参考答案\n\n1. 甲答案\n\n## 线性代数\n\n### 题目\n\n1. 乙题\n\n### 参考答案\n\n1. 乙答案';
 const result=await dom.window.ReaderPaper.prepare(source,{answers:true},()=>null);
 const wrapper=dom.window.document.createElement('div');wrapper.innerHTML=result.html;
 const appendix=wrapper.querySelector('.paper-answers');
 assert.deepEqual(Array.from(appendix.querySelectorAll('h2'),n=>n.textContent),['微积分','线性代数']);
 }finally{dom.window.close();}
});

test('writing area keeps a complete inline sentence with its formulas',async()=>{
 const dom=paper();try{
 const result=await dom.window.ReaderPaper.prepare('1. 对上一课数据取 $w=1,b=1$，计算平方损失。\n\n## 参考答案\n\n1. 解答',{answers:false,space:'medium'},()=>null);
 const wrapper=dom.window.document.createElement('div');wrapper.innerHTML=result.html;
 const tail=wrapper.querySelector('.paper-tail');assert.match(tail.textContent,/对上一课数据取/);assert.match(tail.textContent,/计算平方损失/);assert.ok(tail.querySelector('[data-math-source]'));
 }finally{dom.window.close();}
});
