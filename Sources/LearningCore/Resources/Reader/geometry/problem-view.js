(function() {
  'use strict';
  const root=document.body,plot=document.getElementById('space');
  const formula=document.getElementById('equation'),description=document.getElementById('detail');
  const params=document.getElementById('parameters'),layers=document.getElementById('layers');
  const state=new GeometryViewState(),id=decodeURIComponent(location.hash.slice(1));
  const parameters={},visibility=new Map(),colors={},cache=new GeometryRuntime.GeometryCache();
  const initial=ProblemScenes.build(id);
  const progress=document.getElementById('progress'),stepLabel=document.getElementById('step-label'),play=document.getElementById('play');
  const playback=new GeometryPlayback(initial.steps.length);
  let active=window===parent,ready=false,animation=0,lastFrame=0,dragging=false,modelKey='',records=[],lastHeight=0;
  const scheduler=new GeometryRuntime.GeometryScheduler(paint);
  const draw=(reason='geometry')=>{if(active)scheduler.request(reason);};
  const canvasWidth=document.getElementById('canvas-width'),canvasHeight=document.getElementById('canvas-height');
  const publish=()=>{if(window!==parent)parent.postMessage({type:'math-preview-state',state:GeometryRuntime.snapshot(state,{
    parameters:{...parameters},visibility:Object.fromEntries(visibility),progress:playback.progress,
    width:Number(canvasWidth.value),height:Number(canvasHeight.value)
  })},'*');};
  function pause(){playback.pause();cancelAnimationFrame(animation);play.textContent='播放';}
  function advance(time) {
    if(!playback.playing||!active)return;
    if(time-lastFrame>=40){lastFrame=time;playback.tick(time);progress.value=playback.progress;draw('progress');}
    if(playback.playing)animation=requestAnimationFrame(advance);else{pause();draw('progress');publish();}
  }
  progress.max=initial.steps.length;progress.value=initial.steps.length;
  progress.addEventListener('input',()=>{pause();playback.seek(Number(progress.value));draw('progress');publish();});
  play.addEventListener('click',()=>{
    if(playback.playing){pause();publish();return;}
    playback.play();play.textContent='暂停';lastFrame=0;animation=requestAnimationFrame(advance);
  });
  document.getElementById('previous-step').addEventListener('click',()=>{
    pause();playback.seek(Math.ceil(playback.progress)-1);progress.value=playback.progress;draw('progress');publish();
  });
  document.getElementById('next-step').addEventListener('click',()=>{
    pause();playback.seek(playback.progress>=playback.limit?1:Math.floor(playback.progress)+1);
    progress.value=playback.progress;draw('progress');publish();
  });
  function sizeCanvas() {
    plot.style.width=canvasWidth.value+'%';plot.style.height=canvasHeight.value+'px';
    document.getElementById('width-value').textContent=canvasWidth.value+'%';
    document.getElementById('height-value').textContent=canvasHeight.value+'px';publish();
  }
  canvasWidth.addEventListener('input',sizeCanvas);canvasHeight.addEventListener('input',sizeCanvas);
  for(const button of document.querySelectorAll('[data-size]'))button.addEventListener('click',()=>{
    canvasHeight.value=Math.max(320,Math.min(1000,Number(canvasHeight.value)+Number(button.dataset.size)));sizeCanvas();
  });
  state.displayRadius=id==='sphere-plane-circle'?6:id==='homework-10'?5:3;
  const initialRadius=state.displayRadius;
  for(const option of initial.controls) {
    parameters[option.key]=option.value;
    const label=document.createElement('label');label.textContent=option.label+' ';
    const input=document.createElement(option.choices?'select':'input');input.dataset.parameter=option.key;
    if(option.choices)option.choices.forEach((name,index)=>{const item=document.createElement('option');item.value=index;item.textContent=name;input.append(item);});
    else{input.type='range';input.min=option.min;input.max=option.max;input.step=option.step;}
    input.value=option.value;input.setAttribute('aria-label',option.label);
    const output=document.createElement('output');output.textContent=option.value;
    input.addEventListener('input',()=>{
      dragging=input.type==='range';parameters[option.key]=Number(input.value);output.textContent=input.value;draw();publish();
    });
    input.addEventListener('change',()=>{dragging=false;draw();});
    label.append(input);if(!option.choices)label.append(output);params.append(label);
  }
  document.getElementById('title').textContent=initial.title;
  document.getElementById('range').addEventListener('change',event=>{
    const radius=Number(event.target.value);
    if(!Number.isFinite(radius)||radius<1||radius>50){event.target.reportValidity();return;}
    state.setRenderRadius(radius);draw();publish();
  });
  document.getElementById('fit').addEventListener('click',()=>{state.fitDrawing();draw('view');publish();});
  document.getElementById('reset').addEventListener('click',()=>{state.resetView();state.displayRadius=initialRadius;draw('view');publish();});
  for(const button of document.querySelectorAll('[data-zoom]'))button.addEventListener('click',()=>{
    state.zoom(Number(button.dataset.zoom));draw('view');publish();
  });
  plot.addEventListener('wheel',event=>{
    if(!ready)return;event.preventDefault();event.stopImmediatePropagation();
    state.zoom(Math.exp(Math.max(-100,Math.min(100,event.deltaY))*.002));draw('view');publish();
  },{passive:false,capture:true});
  const trace=(geometry,layer)=>{
    const color=colors[layer.color];
    if(geometry.type==='surface')return GeometryTraces.surface(geometry.points,layer.name,color,layer.color==='gray'?.14:.3);
    const result=GeometryTraces.line(geometry.points,layer.name,color,layer.dash?3:6,layer.dash?'dash':'solid');
    if(geometry.points.length===1)Object.assign(result,{mode:'markers+text',text:[layer.name],textposition:'top center',textfont:{color:colors.text}});
    return result;
  };
  async function paint(reason) {
    if(!active)return;
    try {
      if(ready&&reason==='view'){
        const range=[-state.displayRadius,state.displayRadius];
        await Plotly.relayout(plot,{'scene.camera':structuredClone(state.camera),'scene.xaxis.range':range,'scene.yaxis.range':range,'scene.zaxis.range':range});return;
      }
      if(ready&&reason==='resize'){await Plotly.Plots.resize(plot);return;}
      const css=getComputedStyle(root);
      for(const name of ['page','text','grid','blue','orange','green','purple','red','gray'])colors[name]=css.getPropertyValue('--'+name).trim();
      const density=dragging?.5:1;
      const geometryKey=JSON.stringify([parameters,state.renderRadius,density]);
      const model=cache.get(geometryKey,()=>SpaceGeometry.withSampling(density,()=>ProblemScenes.build(id,parameters,state.renderRadius)));
      const nextKey=geometryKey+JSON.stringify(colors),changed=!ready||nextKey!==modelKey;
      playback.limit=model.steps.length;progress.max=model.steps.length;
      playback.progress=Math.min(playback.limit,playback.progress);
      const shown=ProblemScenes.atProgress(model,playback.progress);
      const stepIndex=Math.min(model.steps.length-1,Math.max(0,Math.ceil(playback.progress)-1));
      stepLabel.textContent=playback.progress===0?'准备：点击下一步观察构造':model.steps[stepIndex].name+'：'+model.steps[stepIndex].description;
      for(const layer of model.layers) {
        if(!visibility.has(layer.key))visibility.set(layer.key,layer.visible!==false);
        let label=layers.querySelector('[data-layer="'+layer.key+'"]');
        if(!label){
          label=document.createElement('label');label.dataset.layer=layer.key;
          const input=document.createElement('input');input.type='checkbox';
          input.addEventListener('change',()=>{visibility.set(layer.key,input.checked);draw('visibility');publish();});
          const swatch=document.createElement('span');swatch.className='layer-swatch';
          const name=document.createElement('span');name.className='layer-name';
          label.append(input,swatch,name);layers.append(label);
        }
        label.querySelector('input').checked=visibility.get(layer.key);
        label.querySelector('.layer-swatch').style.backgroundColor=colors[layer.color];
        label.querySelector('.layer-name').textContent=layer.name;
        label.classList.toggle('pending-layer',!shown.some(item=>item.key===layer.key));
      }
      const tex='\\('+model.equation+'\\)';
      if(formula.dataset.tex!==tex){
        MathJax.typesetClear([formula]);formula.textContent=tex;formula.dataset.tex=tex;await MathJax.typesetPromise([formula]);
      }
      description.textContent=model.description;
      if(changed){
        records=model.layers.flatMap(layer=>layer.geometry.map((geometry,index)=>({layer,geometry,index,shape:'',visible:false})));
        const data=records.map(record=>({...trace(record.geometry,record.layer),visible:false,showlegend:false}));
        const axis={range:[-state.displayRadius,state.displayRadius],gridcolor:colors.grid,color:colors.text,zerolinecolor:colors.grid,autorange:false};
        await Plotly.react(plot,data,{
          margin:{l:0,r:0,t:0,b:0},paper_bgcolor:colors.page,font:{family:css.fontFamily,color:colors.text},
          scene:{xaxis:{...axis,title:'x'},yaxis:{...axis,title:'y'},zaxis:{...axis,title:'z'},aspectmode:'cube',camera:structuredClone(state.camera),bgcolor:colors.page},
          uirevision:id
        },{responsive:false,displayModeBar:false,scrollZoom:false,displaylogo:false});
        modelKey=nextKey;
        if(!ready)plot.on('plotly_relayout',event=>{if(event['scene.camera']){state.setCamera(event['scene.camera']);publish();}});
        ready=true;
      }
      const indices=[],visible=[],updated=[],coordinates={x:[],y:[],z:[]};
      for(let index=0;index<records.length;index++){
        const record=records[index],geometry=shown.find(layer=>layer.key===record.layer.key)?.geometry[record.index];
        const show=!!visibility.get(record.layer.key)&&!!geometry;
        if(record.visible!==show){record.visible=show;indices.push(index);visible.push(show);}
        if(!geometry)continue;
        const shape=geometry.type==='surface'?geometry.points.length+':'+geometry.points[0].length:String(geometry.points.length);
        if(shape!==record.shape){
          const current=trace(geometry,record.layer);
          updated.push(index);for(const axis of ['x','y','z'])coordinates[axis].push(current[axis]);record.shape=shape;
        }
      }
      if(indices.length)await Plotly.restyle(plot,{visible},indices);
      if(updated.length)await Plotly.restyle(plot,coordinates,updated);
      document.getElementById('error').textContent='';
      if(window!==parent)parent.postMessage({type:'math-preview-rendered'},'*');
    } catch(error){
      document.getElementById('error').textContent='图形加载失败：'+error.message;
      if(window!==parent)parent.postMessage({type:'math-preview-error',message:error.message},'*');
    } finally {publish();}
  }
  const resize=new ResizeObserver(()=>{
    if(ready&&active)draw('resize');
    const height=Math.ceil(document.getElementById('error').getBoundingClientRect().bottom+scrollY+12);
    if(window!==parent&&height!==lastHeight){lastHeight=height;parent.postMessage({type:'math-preview-size',height},'*');}
  });resize.observe(plot);
  window.addEventListener('message',event=>{
    if(event.source!==parent)return;
    if(event.data?.type==='math-preview-init'){
      const saved=event.data.state;GeometryRuntime.restore(state,saved);
      if(saved){
        for(const input of params.querySelectorAll('[data-parameter]')){
          const value=saved.parameters?.[input.dataset.parameter];
          if(Number.isFinite(value)){input.value=value;parameters[input.dataset.parameter]=Number(input.value);const output=input.parentElement.querySelector('output');if(output)output.textContent=input.value;}
        }
        for(const [key,value] of Object.entries(saved.visibility||{}))visibility.set(key,Boolean(value));
        if(Number.isFinite(saved.progress)){playback.seek(saved.progress);progress.value=playback.progress;}
        if(Number.isFinite(saved.width))canvasWidth.value=saved.width;
        if(Number.isFinite(saved.height))canvasHeight.value=saved.height;
        document.getElementById('range').value=state.renderRadius;sizeCanvas();
      }
      active=!!event.data.visible;draw();return;
    }
    if(event.data?.type==='math-preview-suspend'){active=false;pause();scheduler.cancel();publish();return;}
    if(event.data?.type==='math-preview-visibility'){
      const wasActive=active;active=Boolean(event.data.visible);
      if(active&&!wasActive)draw();else if(!active){pause();scheduler.cancel();publish();}
    }
  });
  document.addEventListener('visibilitychange',()=>{if(document.hidden)pause();});
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change',()=>draw());
  if(window!==parent)parent.postMessage({type:'math-preview-ready'},'*');
  else draw();
})();
