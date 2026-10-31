const fs=require('node:fs'),path=require('node:path');
const {JSDOM}=require('jsdom');
const root=path.resolve(__dirname,'../Sources/LearningCore/Resources/Reader');
(async()=>{
 const dom=new JSDOM('<main id="article"></main>',{runScripts:'outside-only',url:'https://offline.test/'}),w=dom.window;
 for(const file of ['vendor/marked.min.js','vendor/marked-cjk-friendly.min.js','vendor/purify.min.js','vendor/turndown-7.2.2.js','vendor/turndown-plugin-gfm-1.0.2.js','selection-copy.js','markdown.js','math-config.js','vendor/mathjax/tex-svg.js'])w.eval(fs.readFileSync(path.join(root,file),'utf8'));
 await w.MathJax.startup.promise;
 const library=JSON.parse(fs.readFileSync(process.argv[2])).glossary;
 let formulas=0;
 for(const term of library.terms){
  const article=w.document.getElementById('article');w.MathJax.typesetClear([article]);article.innerHTML=w.ReaderMarkdown.render(term.body,v=>v,false);await w.MathJax.typesetPromise([article]);
  const bad=article.querySelector('[data-mjx-error],[data-mml-node="merror"]');if(bad)throw new Error(term.id+': '+bad.outerHTML);
  formulas+=article.querySelectorAll('mjx-container').length;
 }
 console.log(library.terms.length+' terms and '+formulas+' formula occurrences rendered without errors');dom.window.close();
})().catch(e=>{console.error(e);process.exitCode=1;});
