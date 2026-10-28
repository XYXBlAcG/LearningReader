const test=require('node:test');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../../Sources/LearningCore/Resources/Reader');
function read(source){
 const dom=new JSDOM('<main id="article"></main>',{runScripts:'outside-only'});
 for(const file of ['vendor/marked.min.js','vendor/marked-cjk-friendly.min.js','vendor/purify.min.js','vendor/turndown-7.2.2.js','vendor/turndown-plugin-gfm-1.0.2.js','selection-copy.js','markdown.js','exercise-copy.js','study-questions.js'])dom.window.eval(fs.readFileSync(path.join(root,file),'utf8'));
 const article=dom.window.document.getElementById('article');article.innerHTML=dom.window.ReaderMarkdown.render(source);
 return {dom,items:dom.window.ReaderStudyQuestions.build(article)};
}
test('matches repeated numbers by subject and preserves standalone formulas',()=>{
 const {dom,items}=read('# 练习\n\n## 微积分\n\n1. 求极限\n\n$$\nx^2\n$$\n\n## 线性代数\n\n1. 求行列式\n\n## 参考答案\n\n### 微积分\n\n1. 极限答案\n\n### 线性代数\n\n1. 行列式答案');
 try{assert.equal(items.length,2);assert.match(items[0].question,/x\^2/);assert.match(items[0].answer,/极限答案/);assert.match(items[1].answer,/行列式答案/);assert.notEqual(items[0].id,items[1].id);}finally{dom.window.close();}
});
test('keeps original non-one numbering and marks ambiguous answers',()=>{
 const {dom,items}=read('## 题目\n\n7. 第一题\n8. 第二题\n\n## 参考答案\n\n7. 第一答案\n8. 第二答案');
 try{assert.deepEqual(Array.from(items,x=>x.number),[7,8]);assert.match(items[1].answer,/第二答案/);}finally{dom.window.close();}
 const ambiguous=read('## 甲\n\n1. A\n\n## 乙\n\n1. B\n\n## 参考答案\n\n1. 无法确定');
 try{assert.ok(ambiguous.items.every(x=>!x.answer));}finally{ambiguous.dom.window.close();}
});

test('heading questions keep nested explanations and stable subject-number anchors',()=>{
 const first=read('## 题目\n\n### 第 7 题\n\n**完整条件**\n\n$$\nx=1\n$$\n\n## 参考答案\n\n### 第 7 题\n\n#### 直觉\n\n完整解释\n\n#### 严谨过程\n\n证明');
 const repeated=read('## 题目\n\n### 第 7 题\n\nA\n\n### 第 7 题\n\nB\n\n## 参考答案\n\n### 第 7 题\n\n只有一个答案');
 const second=read('## 题目\n\n### 第 6 题\n\n其他问题\n\n### 第 7 题\n\n**完整条件**\n\n$$\nx=1\n$$\n\n## 参考答案\n\n### 第 7 题\n\n解答');
 try{assert.ok(repeated.items.every(x=>!x.answer));assert.match(first.items[0].answer,/直觉/);assert.match(first.items[0].answer,/严谨过程/);assert.equal(first.items[0].anchor,second.items[1].anchor);assert.match(first.items[0].question,/\*\*完整条件\*\*/);}finally{first.dom.window.close();second.dom.window.close();repeated.dom.window.close();}
});
