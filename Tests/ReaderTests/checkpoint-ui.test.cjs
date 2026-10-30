const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {JSDOM}=require('jsdom');
const fixture=require('../Fixtures/checkpoint.json');
const base=path.resolve(__dirname,'../../Sources/LearningCore/Resources/Reader');
function reader(){
 const dom=new JSDOM('<article></article>',{runScripts:'outside-only',url:'https://offline.test/'});
 for(const f of ['vendor/marked.min.js','vendor/marked-cjk-friendly.min.js','vendor/purify.min.js','vendor/turndown-7.2.2.js','vendor/turndown-plugin-gfm-1.0.2.js','selection-copy.js','checkpoint-core.js','markdown.js','checkpoint-store.js','checkpoint-ui.js','exercise-copy.js','study-questions.js','exercise-paper.js'])dom.window.eval(fs.readFileSync(path.join(base,f),'utf8'));
 return dom;
}
test('checkpoint JSON is extracted before math protection and render never exposes feedback',()=>{
 const dom=reader(),w=dom.window;
 try{const el=w.document.querySelector('article');el.innerHTML=w.ReaderMarkdown.render('# 课\n\n```checkpoint\n'+JSON.stringify(fixture)+'\n```');
 assert.equal(el.querySelectorAll('.checkpoint').length,1);assert.ok(el.querySelector('[data-math-source]'));
 assert.ok(!el.textContent.includes(fixture.explanation));assert.equal(JSON.parse(el.querySelector('.checkpoint').dataset.checkpoint).stem,fixture.stem);
 assert.equal(w.ReaderExerciseCopy.questionRanges([...el.children],false).length,0);
 }finally{dom.window.close();}
});
test('session retains first failure, reveal and draft modes without simulating UI events',async()=>{
 const dom=reader(),w=dom.window;
 try{
 const channel={state:{attempts:[],drafts:[]},async request(c){
  if(c.action==='submit'||c.action==='reveal')this.state.attempts.push({questionID:c.questionID,signature:c.signature,selected:c.selected,action:c.action,correct:c.action==='submit'?w.ReaderCheckpoints.grade(fixture,c.selected).correct:null});
  this.state.drafts=[{questionID:c.questionID,signature:c.signature,selected:c.selected,mode:c.action==='draft'?c.mode:'feedback'}];return this.state;
 }};
 const session=new w.ReaderCheckpointUI.Session(fixture,channel);
 await session.choose(['two']);await session.submit();assert.match(session.status(),/需回看/);
 await session.retry();assert.equal(session.mode,'editing');await session.choose(['one']);await session.submit();assert.match(session.status(),/需回看/);assert.equal(channel.state.attempts.length,2);
 await session.retry();await session.reveal();assert.equal(channel.state.attempts.at(-1).action,'reveal');
 await session.skip();assert.equal(session.mode,'skipped');
 const restored=new w.ReaderCheckpointUI.Session(fixture,channel);assert.equal(restored.mode,'skipped');
 }finally{dom.window.close();}
});
test('paper projects questions and optional answers, never prints raw checkpoint JSON',async()=>{
 const dom=reader(),w=dom.window;
 try{const source='# 课\n\n```checkpoint\n'+JSON.stringify(fixture)+'\n```';
 const paper=await w.ReaderPaper.prepare(source,{answers:false});assert.equal(paper.questionCount,1);assert.ok(!paper.html.includes('data-checkpoint'));assert.ok(!paper.html.includes(fixture.explanation));
 const solved=await w.ReaderPaper.prepare(source,{answers:true});assert.ok(solved.html.includes(fixture.explanation));
 }finally{dom.window.close();}
});

test('a failed acknowledgement retries the same event id and reveal never becomes an independent pass',async()=>{
 const dom=reader(),w=dom.window;
 try{
  const ids=[];const channel={state:{attempts:[],drafts:[{questionID:fixture.id,signature:w.ReaderCheckpoints.signature(fixture),selected:['one'],mode:'editing'}]},async request(c){ids.push(c.eventID);if(ids.length===1)throw Error('reply lost');return this.state;}};
  const session=new w.ReaderCheckpointUI.Session(fixture,channel);
  await assert.rejects(session.submit());await session.submit();assert.equal(ids[0],ids[1]);
  channel.state.attempts=[{questionID:fixture.id,signature:session.signature,action:'reveal',correct:null},{questionID:fixture.id,signature:session.signature,action:'submit',correct:true}];
  assert.match(session.status(),/已看解析/);
 }finally{dom.window.close();}
});

test('static card mounting restores native state and visible copy excludes hidden explanations',async()=>{
 const dom=reader(),w=dom.window;
 try{
  w.webkit={messageHandlers:{readerCheckpoint:{postMessage:async()=>({attempts:[],drafts:[]})}}};
  const article=w.document.querySelector('article');article.innerHTML=w.ReaderMarkdown.render('# 课\n\n```checkpoint\n'+JSON.stringify(fixture)+'\n```');
  const view=await w.ReaderCheckpointUI.mount(article,{courseID:'math'});
  assert.equal(article.querySelectorAll('input[type="radio"]').length,2);assert.match(article.querySelector('summary').textContent,/0\/1/);
  const source=w.ReaderSelectionCopy.nodesMarkdown([...article.children]);assert.ok(!source.includes('explanation'));assert.ok(!source.includes(fixture.options[0].feedback));
  view.dispose();
 }finally{dom.window.close();}
});

test('restored feedback names missing and extra options explicitly',async()=>{
 const dom=reader(),w=dom.window;
 try{
  const signature=w.ReaderCheckpoints.signature(fixture);
  w.webkit={messageHandlers:{readerCheckpoint:{postMessage:async()=>({attempts:[{questionID:fixture.id,signature,selected:['two'],action:'submit',correct:false}],drafts:[{questionID:fixture.id,signature,selected:['two'],mode:'feedback'}]})}}};
  const article=w.document.querySelector('article');article.innerHTML=w.ReaderMarkdown.render('```checkpoint\n'+JSON.stringify(fixture)+'\n```');
  const view=await w.ReaderCheckpointUI.mount(article,{courseID:'math'});
  assert.match(article.querySelector('.checkpoint-feedback').textContent,/漏选 A.*误选 B/);
  view.dispose();
 }finally{dom.window.close();}
});
