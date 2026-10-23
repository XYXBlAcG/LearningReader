(function(root) {
  'use strict';
  let observer=null;
  const frames=new Set();
  const states=new WeakMap();
  const savedViews=new Map();
  let enabled=true;
  let pending=0;
  const post=(frame,data)=>frame.contentWindow?.postMessage(data,'*');
  function unload(frame) {
    const state=states.get(frame);if(!state)return;
    clearTimeout(state.timer);state.releasing=false;state.live=false;
    frame.removeAttribute('src');frame.dataset.visible='false';
    const status=frame.closest('figure').querySelector('.preview-status');
    status.hidden=false;status.textContent='滚动到此处加载三维预览';
    schedule();
  }
  function release(frame) {
    const state=states.get(frame);if(!state.live||state.releasing)return;
    state.releasing=true;
    post(frame,{type:'math-preview-suspend'});
    state.timer=setTimeout(()=>unload(frame),500);
  }
  function schedule() {
    if(pending)return;
    pending=requestAnimationFrame(()=>{
      pending=0;
      const candidates=[...frames].filter(frame=>{
        const state=states.get(frame),modal=frame.closest('dialog').matches(':modal');
        return enabled&&!document.hidden&&(modal||(state.eligible&&!frame.closest('details:not([open])')));
      }).sort((a,b)=>{
        const am=a.closest('dialog').matches(':modal'),bm=b.closest('dialog').matches(':modal');
        if(am!==bm)return am?-1:1;
        const center=window.innerHeight/2;
        return Math.abs(a.getBoundingClientRect().top-center)-Math.abs(b.getBoundingClientRect().top-center);
      }).slice(0,2);
      for(const frame of frames)if(!candidates.includes(frame))release(frame);
      let live=[...frames].filter(frame=>states.get(frame).live).length;
      for(const frame of candidates) {
        const state=states.get(frame);
        if(state.releasing)continue;
        if(!state.live&&live<2) {
          state.live=true;live++;
          const status=frame.closest('figure').querySelector('.preview-status');
          status.hidden=false;status.textContent='正在加载三维预览…';
          frame.loading='eager';frame.src=frame.dataset.previewSrc;
        }
        if(state.live){frame.dataset.visible='true';post(frame,{type:'math-preview-visibility',visible:true});}
      }
    });
  }
  function setEnabled(value) {
    enabled=value;
    document.body.classList.toggle('previews-disabled',!enabled);
    for(const frame of frames) {
      if(enabled)observer?.observe(frame);
      else {observer?.unobserve(frame);release(frame);}
    }
    schedule();
  }
  window.addEventListener('message',event=>{
    for(const frame of frames)if(event.source===frame.contentWindow) {
      const figure=frame.closest('figure');
      const status=figure.querySelector('.preview-status');
      const state=states.get(frame);
      if(!state.live)return;
      if(event.data?.type==='math-preview-state') {
        savedViews.delete(frame.dataset.previewSrc);savedViews.set(frame.dataset.previewSrc,event.data.state);
        if(savedViews.size>48)savedViews.delete(savedViews.keys().next().value);
        if(state.releasing)unload(frame);
      }
      if(event.data?.type==='math-preview-ready')post(frame,{type:'math-preview-init',state:savedViews.get(frame.dataset.previewSrc),visible:!state.releasing&&frame.dataset.visible==='true'});
      if(event.data?.type==='math-preview-rendered')status.hidden=true;
      if(event.data?.type==='math-preview-error') {
        status.textContent='三维预览加载失败：'+event.data.message;status.hidden=false;
      }
      if(event.data?.type==='math-preview-size'&&Number.isFinite(event.data.height)&&!figure.querySelector('dialog').matches(':modal')) {
        figure.querySelector('.interactive-viewport').style.height=Math.max(320,Math.min(2400,event.data.height))+'px';
      }
    }
  });
  function dispose() {
    cancelAnimationFrame(pending);pending=0;
    if(observer)observer.disconnect();
    for(const frame of frames){clearTimeout(states.get(frame)?.timer);frame.removeAttribute('src');}
    frames.clear();
  }
  function enhance(article) {
    observer=new IntersectionObserver(entries=>{
      for(const entry of entries) {
        const frame=entry.target;
        states.get(frame).eligible=entry.isIntersecting;
      }
      schedule();
    },{root:article,rootMargin:'0px'});
    for(const frame of article.querySelectorAll('iframe[data-preview-src]')) {
      const figure=frame.closest('figure');
      if(!figure.querySelector('.preview-status')) {
        const status=document.createElement('p');status.className='preview-status';status.setAttribute('role','status');
        status.textContent='滚动到此处加载三维预览';figure.querySelector('.interactive-viewport').prepend(status);
      }
      const holder=figure.parentElement.tagName==='P'?figure.parentElement:figure;
      const heading=holder.previousElementSibling;
      if(heading&&/^H[1-6]$/.test(heading.tagName)&&figure.classList.contains('problem-preview')) {
        const group=document.createElement('section');group.className='answer-preview';
        const text=document.createElement('div');text.className='answer-preview-text';
        const level=Number(heading.tagName.slice(1));
        heading.before(group);
        let node=heading;
        while(node&&(!/^H[1-6]$/.test(node.tagName)||node===heading||Number(node.tagName.slice(1))>level)) {
          const next=node.nextElementSibling;text.append(node);node=next;
        }
        const controls=document.createElement('div');controls.className='preview-layout-controls';
        const label=document.createElement('label');label.textContent='正文宽度 ';
        const ratio=document.createElement('input');ratio.type='range';ratio.min=35;ratio.max=75;ratio.step=1;
        ratio.setAttribute('aria-label','正文与三维预览的宽度比例');
        const output=document.createElement('output');
        const separator=document.createElement('div');separator.className='preview-divider';separator.tabIndex=0;
        separator.setAttribute('role','separator');separator.setAttribute('aria-label','调整正文与三维预览宽度');separator.setAttribute('aria-orientation','vertical');
        separator.setAttribute('aria-valuemin','35');separator.setAttribute('aria-valuemax','75');
        function setRatio(value) {
          const width=Math.max(35,Math.min(75,Math.round(value)));
          ratio.value=width;output.textContent=width+'%';separator.setAttribute('aria-valuenow',width);
          group.style.setProperty('--text-share',width+'fr');group.style.setProperty('--plot-share',(100-width)+'fr');
          localStorage.setItem('reader_preview_text_width',width);
        }
        setRatio(Number(localStorage.getItem('reader_preview_text_width'))||60);
        ratio.addEventListener('input',()=>setRatio(Number(ratio.value)));
        separator.addEventListener('pointerdown',event=>{separator.setPointerCapture(event.pointerId);});
        separator.addEventListener('pointermove',event=>{
          if(!separator.hasPointerCapture(event.pointerId))return;
          const bounds=group.getBoundingClientRect();setRatio(100*(event.clientX-bounds.left)/bounds.width);
        });
        separator.addEventListener('pointerup',event=>separator.releasePointerCapture(event.pointerId));
        separator.addEventListener('keydown',event=>{
          if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
          event.preventDefault();setRatio(event.key==='Home'?35:event.key==='End'?75:Number(ratio.value)+(event.key==='ArrowLeft'?-2:2));
        });
        label.append(ratio,output);controls.append(label);
        group.append(controls,text,separator,figure);
        if(holder!==figure&&!holder.textContent.trim())holder.remove();
      }
      frame.addEventListener('load',()=>{
        if(!frame.hasAttribute('src'))return;
        if(!figure.classList?.contains('problem-preview'))figure.querySelector('.preview-status').hidden=true;
      });
      figure.querySelector('.embed-fullscreen').addEventListener('click',schedule);
      figure.querySelector('dialog').addEventListener('close',schedule);
      frames.add(frame);
      states.set(frame,{eligible:false,live:false,releasing:false,timer:0});
    }
  }
  function activate() {
    if(enabled)for(const frame of frames)observer.observe(frame);
  }
  document.addEventListener('visibilitychange',()=>{
    if(document.hidden)for(const frame of frames)release(frame);
    else schedule();
  });
  document.addEventListener('toggle',schedule,true);
  root.ReaderProblemPreviews={dispose,enhance,activate,setEnabled};
})(window);
