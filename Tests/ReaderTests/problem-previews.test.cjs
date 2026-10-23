const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

function harness() {
  const messages=[];
  const listeners={};
  const frameEvents={};
  const status={textContent:'',hidden:false,setAttribute(){},className:''};
  const viewport={style:{}};
  const dialog={matches:()=>false,addEventListener(){}};
  const button={addEventListener(){}};
  const figure={previousElementSibling:null,parentElement:{tagName:'DIV'},classList:{contains:()=>false},querySelector:selector=>selector==='dialog'?dialog:selector==='.interactive-viewport'?viewport:selector==='.preview-status'?status:button};
  const frame={dataset:{previewSrc:'/media/preview.html#test'},loading:'lazy',closest:selector=>selector==='dialog'?dialog:selector.startsWith('details')?null:figure,contentWindow:{postMessage:data=>messages.push(data)},addEventListener:(name,fn)=>frameEvents[name]=fn,hasAttribute:()=>Boolean(frame.src),removeAttribute:()=>delete frame.src};
  const window={addEventListener:(name,fn)=>listeners[name]=fn};
  let observe;
  class IntersectionObserver {
    constructor(callback){observe=callback;}
    observe(){}
    disconnect(){}
    unobserve(){}
  }
  const animations=[];
  const flush=()=>{const current=animations.splice(0);current.forEach(callback=>callback());};
  vm.runInNewContext(fs.readFileSync(require.resolve('../../Sources/LearningCore/Resources/Reader/problem-previews.js'),'utf8'),{window,document:{hidden:false,addEventListener(){},body:{classList:{toggle(){}}}},IntersectionObserver,requestAnimationFrame:callback=>{animations.push(callback);return animations.length;},cancelAnimationFrame(){},setTimeout:()=>1,clearTimeout(){}});
  window.ReaderProblemPreviews.enhance({querySelectorAll:()=>[frame]});
  return {frame,status,viewport,messages,frameEvents,setEnabled:value=>{window.ReaderProblemPreviews.setEnabled(value);flush();},intersect:visible=>{observe([{target:frame,isIntersecting:visible}]);flush();},message:data=>{listeners.message({source:frame.contentWindow,data});flush();}};
}

test('the reader owns lazy loading and gives a newly loaded frame its current visibility',()=>{
  const h=harness();
  h.intersect(true);
  assert.equal(h.frame.src,'/media/preview.html#test');
  assert.equal(h.frame.loading,'eager');
  assert.match(h.status.textContent,/加载/);
  h.frameEvents.load();
  assert.equal(h.messages.at(-1).visible,true);
  h.intersect(false);
  h.message({type:'math-preview-ready'});
  assert.equal(h.messages.at(-1).visible,false);
});

test('render errors and canvas size are reflected beside the embedded frame',()=>{
  const h=harness();
  h.intersect(true);
  h.message({type:'math-preview-error',message:'WebGL unavailable'});
  assert.match(h.status.textContent,/WebGL unavailable/);
  assert.equal(h.status.hidden,false);
  h.message({type:'math-preview-rendered'});
  assert.equal(h.status.hidden,true);
  h.message({type:'math-preview-size',height:940});
  assert.equal(h.viewport.style.height,'940px');
});

test('disabled previews never load and disabling a loaded frame unloads it',()=>{
  const h=harness();
  h.setEnabled(false);
  h.intersect(true);
  assert.equal(h.frame.src,undefined);
  h.setEnabled(true);
  h.intersect(true);
  assert.ok(h.frame.src);
  h.setEnabled(false);
  assert.equal(h.messages.at(-1).type,'math-preview-suspend');
  h.message({type:'math-preview-state',state:{}});
  assert.equal(h.frame.src,undefined);
});

test('uncaught scene initialization errors are visible instead of leaving a blank frame',()=>{
  const error={textContent:''};
  const messages=[];
  let onError;
  const document={currentScript:{src:'http://localhost/reader/geometry/bootstrap.js'},body:{dataset:{mode:'problem'}},createElement:()=>({}),head:{append(){}},getElementById:()=>error};
  vm.runInNewContext(fs.readFileSync(require.resolve('../../Sources/LearningCore/Resources/Reader/geometry/bootstrap.js'),'utf8'),{document,URL,window:{addEventListener:(name,fn)=>{onError=fn;}},parent:{postMessage:message=>messages.push(message)}});
  onError({message:'未知题目图形'});
  assert.match(error.textContent,/未知题目图形/);
  assert.equal(messages[0].type,'math-preview-error');
});
