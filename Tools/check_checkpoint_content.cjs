const fs=require('node:fs'),path=require('node:path');
const {JSDOM}=require('jsdom');
const core=require('../Sources/LearningCore/Resources/Reader/checkpoint-core.js');
const files=process.argv.slice(2).filter(v=>v!=='--markdown');
if(!files.length)throw Error('提供需要校验的 Markdown 文件路径');
const questions=files.flatMap(file=>core.extract(fs.readFileSync(file,'utf8')).map(b=>b.question));
const text=questions.flatMap(q=>[q.stem,...q.options.flatMap(o=>[o.text,o.feedback]),q.explanation]).join('\n\n');
if(process.argv.includes('--markdown')){process.stdout.write(text+'\n');process.exit(0);}
const base=path.resolve(__dirname,'../Sources/LearningCore/Resources/Reader');
const dom=new JSDOM('<article></article>',{runScripts:'outside-only',url:'https://offline.test/'}),w=dom.window;
for(const file of ['vendor/marked.min.js','vendor/marked-cjk-friendly.min.js','vendor/purify.min.js','vendor/turndown-7.2.2.js','vendor/turndown-plugin-gfm-1.0.2.js','selection-copy.js','markdown.js','math-config.js','vendor/mathjax/tex-svg.js'])w.eval(fs.readFileSync(path.join(base,file),'utf8'));
(async()=>{
 await w.MathJax.startup.promise;
 const article=w.document.querySelector('article');article.innerHTML=w.ReaderMarkdown.render(text);
 const formulas=article.querySelectorAll('[data-math-source]').length;
 await w.MathJax.typesetPromise([article]);
 const errors=[...article.querySelectorAll('[data-mjx-error],mjx-merror,[data-mml-node="merror"]')];
 if(errors.length)throw Error(errors.map(e=>e.textContent).join('\n'));
 console.log(questions.length+' 道题的协议与 '+formulas+' 处公式排版通过');dom.window.close();
})().catch(error=>{console.error(error);dom.window.close();process.exitCode=1;});
