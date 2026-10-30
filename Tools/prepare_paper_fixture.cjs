const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const root=path.resolve(__dirname,'..'),reader=path.join(root,'Sources/LearningCore/Resources/Reader');
(async()=>{
 const dom=new JSDOM('<main id="article"></main>',{runScripts:'outside-only'});
 try{
  for(const file of ['vendor/marked.min.js','vendor/marked-cjk-friendly.min.js','vendor/purify.min.js','vendor/turndown-7.2.2.js','vendor/turndown-plugin-gfm-1.0.2.js','selection-copy.js','markdown.js','exercise-copy.js','study-questions.js','exercise-paper.js'])dom.window.eval(fs.readFileSync(path.join(reader,file),'utf8'));
  const output=path.join(root,'build/paper-fixtures');fs.mkdirSync(output,{recursive:true});
  const course=fs.readFileSync(path.join(root,'Templates/machine-learning-course/exercises/01-introduction.md'),'utf8');
  const image='data:image/svg+xml;base64,'+Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="300" height="100"><rect width="300" height="100" fill="white"/><path d="M10 90 L150 10 L290 90 Z" fill="none" stroke="black" stroke-width="3"/></svg>').toString('base64');
  const longFormula='$$'+Array.from({length:32},(_,i)=>'x_{'+(i+1)+'}').join('+')+'=0$$';
  const stress='# 打印排版检查\n\n保留说明、公式与题图。\n\n1. 求值。\n\n$$\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}$$\n\n![三角形]('+image+')\n\n'+longFormula+'\n\n2. 超长推导。\n\n'+Array.from({length:85},(_,i)=>'第 '+(i+1)+' 步：保留这一推导与条件 $x_'+(i+1)+'=\\frac{1}{2}$。').join('\n\n')+'\n\n## 参考答案\n\n1. 答案附录检查\n2. 完成';
  for(const [name,source,options] of [['questions',course,{answers:false,space:'medium'}],['answers',course,{answers:true,space:'medium'}],['long',stress,{answers:false,space:'large'}]]){
   const payload=await dom.window.ReaderPaper.prepare(source,{title:name,...options},()=>null);
   fs.writeFileSync(path.join(output,name+'.json'),JSON.stringify(payload));
  }
 }finally{dom.window.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
