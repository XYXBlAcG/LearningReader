(async function () {
  'use strict';
  window.addEventListener('error',event=>{
    document.getElementById('error').textContent='绘图程序运行失败：'+event.message;
    if(window!==parent)parent.postMessage({type:'math-preview-error',message:event.message},'*');
  });
  const base=new URL('.',document.currentScript.src).href;
  const style=document.createElement('link');
  style.rel='stylesheet';
  style.href=base+'style.css';
  document.head.append(style);
  const application=document.body.dataset.mode==='problem'?['problem-scenes.js','problem-view.js']:['app.js'];
  const load=name=>new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      script.src=base+name;
      script.onload=resolve;
      script.onerror=()=>reject(new Error(name));
      document.head.append(script);
    });
  await load('../math-config.js');
  await Promise.all([load('plotly-gl3d-3.1.0.min.js'),load('../vendor/mathjax/tex-svg.js')]);
  await MathJax.startup.promise;
  for(const name of ['models.js','view-state.js','runtime.js','traces.js',...application])await load(name);
})().catch(error=>{
  document.getElementById('error').textContent='本地绘图资源加载失败：'+error.message+'。请从阅读器打开。';
  if(window!==parent)parent.postMessage({type:'math-preview-error',message:error.message},'*');
});
