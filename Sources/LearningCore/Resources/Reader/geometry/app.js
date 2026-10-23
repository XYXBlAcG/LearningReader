(function () {
  'use strict';
  const G=window.SpaceGeometry;
  const root=document.body;
  const space=document.getElementById('space');
  const slicePlot=document.getElementById('section');
  const selection=document.getElementById('selection');
  const first=document.getElementById('first');
  const second=document.getElementById('second');
  const axis=document.getElementById('axis');
  const equation=document.getElementById('equation');
  const detail=document.getElementById('detail');
  const mode=root.dataset.mode;
  let active=window===parent;
  const number=value => Math.abs(value)<1e-8?'0':Number(value.toFixed(4)).toString();
  const coordinates=point => '('+point.map(number).join(', ')+')';
  const config={responsive:false,displayModeBar:false,scrollZoom:false,displaylogo:false};

  class GeometryView {
    constructor() {
      this.colors={};
      this.ready=false;
      this.dragging=false;
      this.cache=new GeometryRuntime.GeometryCache();
      this.scheduler=new GeometryRuntime.GeometryScheduler(reason=>this.paint(reason));
      this.state=new window.GeometryViewState();
      this.bound=false;
    }
    palette() {
      const styles=getComputedStyle(root);
      for(const name of ['page','text','muted','grid','blue','orange','green']) this.colors[name]=styles.getPropertyValue('--'+name).trim();
    }
    zoom(factor) {
      if(!this.ready) return;
      this.state.zoom(factor);
      this.draw('view');publish();
      viewStatus.textContent='观察范围 ±'+number(this.state.displayRadius);
    }
    line(points,name,color,width=5,dash='solid') {
      return GeometryTraces.line(points,name,color,width,dash);
    }
    points(points,labels,color) {
      return {type:'scatter3d',mode:'markers+text',x:points.map(p=>p[0]),y:points.map(p=>p[1]),z:points.map(p=>p[2]),text:labels,textposition:'top center',textfont:{color:this.colors.text},marker:{color,size:5},showlegend:false,hoverinfo:'text'};
    }
    surface(patch,name,color,opacity=.38) {
      return GeometryTraces.surface(patch,name,color,opacity);
    }
    plane(axisIndex,height,name,color) {
      const free=[0,1,2].filter(i=>i!==axisIndex);
      const r=this.state.renderRadius;
      return this.surface([-r,r].map(u=>[-r,r].map(v=>{const p=[0,0,0];p[axisIndex]=height;p[free[0]]=u;p[free[1]]=v;return p;})),name,color,.16);
    }
    vector(start,direction,name,color) {
      const end=G.add(start,direction);
      return [this.line([start,end],name,color,3),{type:'cone',x:[end[0]],y:[end[1]],z:[end[2]],u:[direction[0]],v:[direction[1]],w:[direction[2]],anchor:'tip',sizemode:'absolute',sizeref:.2,colorscale:[[0,color],[1,color]],showscale:false,showlegend:false,hoverinfo:'skip'}];
    }
    world() {
      const k=Number(first.value), h=Number(second.value);
      const c=this.colors, data=[];
      let text='',description='';
      const r=this.state.renderRadius;
      const path=(p,d)=>[-r,r].map(t=>G.add(p,G.scale(d,t)));
      switch(selection.value) {
        case 'line-plane': {
          const p=[0,0,h],d=[1,0,k];
          data.push(this.plane(2,0,'平面 z = 0',c.blue),this.line(path(p,d),'直线 L',c.orange),...this.vector([0,-1,0],[0,0,1],'法向量 n',c.blue),...this.vector(p,d,'方向 d',c.orange));
          text='Π: z = 0； L: (x,y,z) = (0,0,'+number(h)+') + t(1,0,'+number(k)+')';
          description=String.raw`\(\mathbf n\cdot\mathbf d=`+number(k)+String.raw`\)`+'；'+(k===0?(h===0?'所有参数都满足方程：直线包含在平面内。':'高度恒为 '+number(h)+'：直线与平面严格平行。'):String.raw`相交，交点参数 \(t=`+number(-h/k)+String.raw`\)。`);
          if(k!==0) data.push(this.points([[-h/k,0,0]],['交点'],c.green));
          break;
        }
        case 'planes': {
          data.push(this.plane(2,0,'Π₁',c.blue));
          if(k!==0||h!==0) data.push(this.surface([-r,r].map(x=>[-r,r].map(y=>[x,y,k*x+h])),'Π₂',c.orange,.23));
          data.push(...this.vector([0,1,0],[0,0,1],'n₁',c.blue),...this.vector([0,-1,h],[-k,0,1],'n₂',c.orange));
          text='Π₁: z = 0； Π₂: z = '+number(k)+'x + '+number(h);
          description=k===0?(h===0?'两平面重合。':'法向量相同、位置不同：两平面严格平行。'):String.raw`交线：\(x=`+number(-h/k)+String.raw`,\ z=0\)，\(y\) 任意；方向 \((0,1,0)\) 与两个法向量均垂直。`;
          if(k!==0) data.push(this.line([[-h/k,-r,0],[-h/k,r,0]],'交线',c.green,7));
          break;
        }
        case 'lines-cross':
        case 'lines-parallel': {
          const parallel=selection.value==='lines-parallel';
          const p=parallel?[0,h,0]:[0,0,h],d=parallel?[1,0,0]:[0,1,0];
          data.push(this.line([[-r,0,0],[r,0,0]],'L₁：x 轴',c.blue),this.line(path(p,d),'L₂',c.orange,5,'dash'));
          text='L₁: (t,0,0)； L₂: '+(parallel?'(s,'+number(h)+',0)':'(0,s,'+number(h)+')');
          description=parallel?(h===0?'两条直线重合。':'两方向相同，但没有公共点：严格平行。'):(h===0?'两方向不平行，有公共点：在原点相交。':'两方向不平行，高度分别为 0 和 '+number(h)+'：异面。俯视时投影相交，但空间中不相交。');
          if(!parallel) data.push(this.line([[0,0,0],[0,0,h]],'最短连接段',c.green,7),this.points([[0,0,0],[0,0,h]],['U','V'],c.green));
          break;
        }
        case 'projection': {
          const p=[0,0,h],d=[1-k,0,k],plane={normal:[0,0,1],constant:0};
          const foot=G.project(p,plane),projected=G.projectDirection(d,plane);
          data.push(this.plane(2,0,'投影平面',c.blue),this.line(path(p,d),'原直线',c.orange));
          if(G.norm(projected)>1e-9) data.push(this.line(path(foot,projected),'投影直线',c.green,7));
          else data.push(this.points([foot],['投影点 H'],c.green));
          for(const t of [-1,0,1]) { const q=G.add(p,G.scale(d,t)); data.push(this.line([q,G.project(q,plane)],'垂直投影线',c.grid,2,'dash')); }
          text='Π: z = 0； P = (0,0,'+number(h)+')； d = ('+number(1-k)+',0,'+number(k)+')';
          description=String.raw`去掉竖直分量后 \(\mathbf d_{\text{投影}}=`+coordinates(projected)+String.raw`\)`+'；'+(G.norm(projected)<1e-9?'原线沿法向方向，全部影子重合成一个点。':'投影方向非零，所有影子构成一条直线。');
          break;
        }
      }
      return {data,text:String.raw`\(`+text.replaceAll('；',String.raw`\quad `)+String.raw`\)`,description};
    }
    distance() {
      const t=Number(first.value),s=Number(second.value),r=G.connector(t,s),c=this.colors;
      const extent=this.state.renderRadius;
      const data=[this.line([[-extent,-extent,0],[extent,extent,0]],'L₁',c.blue),this.line([[1,-extent,1-extent],[1,extent,1+extent]],'L₂',c.orange),this.line([r.first,r.second],'当前连接段',c.green,7),this.points([r.first,r.second],['P(t)','Q(s)'],c.green)];
      const closest=G.connector(1/3,-1/3);
      data.push(this.line([closest.first,closest.second],'最短连接段',c.muted,3,'dash'));
      return {data,text:String.raw`\(L_1:(t,t,0)\quad L_2:(1,s,1+s)\)`+'；当前长度 = '+number(r.distance),description:String.raw`连接向量与方向的内积分别为 \(`+number(r.dot1)+String.raw`\)、\(`+number(r.dot2)+String.raw`\)。最短长度 \(\frac{2}{\sqrt{3}}\approx `+number(closest.distance)+String.raw`\)。`};
    }
    quadric() {
      const model=G.quadrics[selection.value],height=Number(first.value),axisIndex=Number(axis.value),c=this.colors;
      const section=G.section(model,axisIndex,height,this.state.renderRadius);
      const patches=this.cache.get(JSON.stringify([selection.value,this.state.renderRadius,this.dragging]),()=>G.surfacePatches(model,this.state.renderRadius));
      const data=patches.map(patch=>this.surface(patch,model.name,c.blue));
      if(document.getElementById('show-plane').checked) data.push(this.plane(axisIndex,height,'切割平面',c.orange));
      section.curves.forEach(branch=>data.push(this.line(branch,'截痕',c.green,7)));
      const names=['x','y','z'],[u,v]=section.free.map(i=>names[i]),[A,B,C,d,e]=section.coefficients;
      const coefficient=value => Math.abs(value-4/9)<1e-9?String.raw`\frac{4}{9}`:Math.abs(value-1)<1e-9?'':number(value);
      const terms=[[A,u+'²'],[2*B,u+v],[C,v+'²'],[d,u],[e,v]].filter(([a])=>Math.abs(a)>1e-9).map(([a,label],index)=> (a<0?'- ':index?'+ ':'')+coefficient(Math.abs(a))+label).join(' ');
      const text=String.raw`\(`+model.equation.replaceAll('²','^2').replaceAll('−','-')+String.raw`\)`+String.raw`；切割平面 \(`+names[axisIndex]+' = '+number(height)+String.raw`\)`;
      const description=String.raw`代入后的方程：\(`+(terms||'0').replaceAll('²','^2')+' = '+number(section.rhs)+String.raw`\)`+'；截痕是'+section.kind+'。';
      const flat=section.curves.map(branch=>({type:'scatter',mode:branch.length===1?'markers':'lines',x:branch.map(p=>p[section.free[0]]),y:branch.map(p=>p[section.free[1]]),line:{color:c.green,width:3},marker:{color:c.green,size:8},showlegend:false,hovertemplate:u+' = %{x:.2f}<br>'+v+' = %{y:.2f}<extra></extra>'}));
      return {data,text,description,flat,free:[u,v],empty:section.curves.length===0,kind:section.kind};
    }
    draw(reason='geometry'){if(active)this.scheduler.request(reason);}
    async paint(reason) {
      if(!active)return;
      try {
        if(this.ready&&reason==='resize'){
          await Plotly.Plots.resize(space);if(slicePlot)await Plotly.Plots.resize(slicePlot);return;
        }
        if(this.ready&&reason==='view'){
          const range=[-this.state.displayRadius,this.state.displayRadius];
          await Plotly.relayout(space,{'scene.camera':structuredClone(this.state.camera),'scene.xaxis.range':range,'scene.yaxis.range':range,'scene.zaxis.range':range});return;
        }
        this.palette();
        const result=G.withSampling(this.dragging?.5:1,()=>mode==='quadric'?this.quadric():mode==='distance'?this.distance():this.world());
        const changed=[];
        for(const [node,text] of [[equation,result.text],[detail,result.description]])if(node.dataset.tex!==text){
          MathJax.typesetClear([node]);node.textContent=text;node.dataset.tex=text;changed.push(node);
        }
        if(changed.length)await MathJax.typesetPromise(changed);
        for(const input of [first,second].filter(Boolean)) document.getElementById(input.id+'-value').textContent=number(Number(input.value));
        const c=this.colors;
        const fontFamily=getComputedStyle(root).fontFamily;
        const axes=label=>({title:{text:label,font:{color:c.text}},range:[-this.state.displayRadius,this.state.displayRadius],gridcolor:c.grid,zerolinecolor:c.muted,showbackground:false,color:c.text});
        await Plotly.react(space,result.data,{paper_bgcolor:c.page,font:{family:fontFamily,color:c.text,size:12},margin:{l:0,r:0,b:0,t:0},showlegend:false,uirevision:'space-camera',scene:{xaxis:axes('x'),yaxis:axes('y'),zaxis:axes('z'),aspectmode:'cube',dragmode:'orbit',camera:structuredClone(this.state.camera)}},config);
        if(mode==='quadric') {
          await Plotly.react(slicePlot,result.flat,{paper_bgcolor:c.page,plot_bgcolor:c.page,font:{family:fontFamily,color:c.text,size:12},margin:{l:45,r:15,b:35,t:25},title:{text:'切割平面内的二维图',font:{size:13}},showlegend:false,uirevision:'section-view',xaxis:{title:{text:result.free[0]},range:this.state.sectionX,gridcolor:c.grid,zerolinecolor:c.muted},yaxis:{title:{text:result.free[1]},range:this.state.sectionY,scaleanchor:'x',scaleratio:1,gridcolor:c.grid,zerolinecolor:c.muted},annotations:result.empty?[{text:result.kind,x:.5,y:.5,xref:'paper',yref:'paper',showarrow:false,font:{color:c.text}}]:[]},config);
        }
        if(!this.bound) {
          space.on('plotly_relayout',event=>{
            if(event['scene.camera']) {this.state.setCamera(event['scene.camera']);publish();}
          });
          if(slicePlot) slicePlot.on('plotly_relayout',()=>{
            this.state.sectionX=[...slicePlot.layout.xaxis.range];
            this.state.sectionY=[...slicePlot.layout.yaxis.range];
            publish();
          });
          this.bound=true;
        }
        this.ready=true;
        viewStatus.textContent='观察范围 ±'+number(this.state.displayRadius);
      } catch(error) {
        document.getElementById('error').textContent='三维图无法初始化，请确认浏览器启用了 WebGL。'+error.message;
      } finally {
        publish();
      }
    }
  }
  const view=new GeometryView();
  const publish=()=>{if(window!==parent)parent.postMessage({type:'math-preview-state',state:GeometryRuntime.snapshot(view.state,{
    selection:selection.value,first:first.value,second:second?.value,axis:axis?.value,
    showPlane:document.getElementById('show-plane')?.checked,plotHeight:space.style.height
  })},'*');};
  let lastHeight=0;
  const resizeObserver=new ResizeObserver(()=>{
    if(view.ready&&active)view.draw('resize');
    const height=Math.ceil(document.getElementById('error').getBoundingClientRect().bottom+scrollY+12);
    if(window!==parent&&height!==lastHeight){lastHeight=height;parent.postMessage({type:'math-preview-size',height},'*');}
  });
  resizeObserver.observe(space);
  if(slicePlot) resizeObserver.observe(slicePlot);
  const zoomControls=document.createElement('div');
  zoomControls.className='views';
  const viewStatus=document.createElement('output');
  viewStatus.id='view-status';
  viewStatus.setAttribute('aria-live','polite');
  for(const [label,factor] of [['放大',.8],['缩小',1.25],['复位',1]]) {
    const button=document.createElement('button');
    button.type='button';
    button.textContent=label;
    button.dataset.zoom=String(factor);
    button.addEventListener('click',()=>{
      if(!view.ready) return;
      if(label==='复位') {
        view.state.resetView();
        view.zoom(1);
        view.draw();
      } else view.zoom(factor);
    });
    zoomControls.append(button);
  }
  const resizeHelp=document.createElement('span');
  resizeHelp.textContent='图内滚轮缩放；右下角拖动调高度';
  zoomControls.append(resizeHelp);
  zoomControls.append(viewStatus);
  document.querySelector('.views').after(zoomControls);
  const extentControls=document.createElement('div');
  extentControls.className='controls';
  const extentLabel=document.createElement('label');
  extentLabel.textContent='绘制范围 R ';
  const extentInput=document.createElement('input');
  extentInput.type='number';
  extentInput.id='render-radius';
  extentInput.setAttribute('aria-label','绘制范围 R');
  extentInput.required=true;
  extentInput.min='3';
  extentInput.max='50';
  extentInput.step='1';
  extentInput.value='3';
  extentInput.style.width='70px';
  extentLabel.append(extentInput);
  const fitButton=document.createElement('button');
  fitButton.type='button';
  fitButton.textContent='适配绘制范围';
  fitButton.addEventListener('click',()=>{
    if(!extentInput.reportValidity()) return;
    view.state.setRenderRadius(Number(extentInput.value));
    view.state.fitDrawing();
    view.draw();
  });
  const updateExtent=()=>{
    if(!extentInput.validity.valid) return;
    view.state.setRenderRadius(Number(extentInput.value));
    const controls=mode==='quadric'?[first]:[first,second];
    for(const control of controls) {
      const limit=Math.max(view.state.renderRadius,Math.abs(Number(control.value)));
      if(mode!=='relations'||control===second){control.min=String(-limit);control.max=String(limit);}
    }
    view.draw();
  };
  extentInput.addEventListener('input',updateExtent);
  extentInput.addEventListener('change',()=>{extentInput.reportValidity();updateExtent();});
  const extentHelp=document.createElement('span');
  extentHelp.textContent='扩大实际绘图片段；视角与缩放保留';
  extentControls.append(extentLabel,fitButton,extentHelp);
  zoomControls.after(extentControls);
  space.addEventListener('wheel',event=>{
    if(!view.ready||event.deltaY===0) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    view.zoom(Math.exp(Math.sign(event.deltaY)*.12));
  },{passive:false,capture:true});
  if(mode==='quadric') {
    for(const [key,model] of Object.entries(G.quadrics)) selection.add(new Option(model.name,key));
    selection.value='ellipsoid';
  }
  const update=()=>{view.draw();publish();};
  for(const control of [selection,first,second,axis,document.getElementById('show-plane')].filter(Boolean)){
    control.addEventListener(control.type==='range'?'input':'change',()=>{view.dragging=control.type==='range';update();});
    if(control.type==='range')control.addEventListener('change',()=>{view.dragging=false;update();});
  }
  if(mode==='relations') selection.addEventListener('change',()=>{
    document.getElementById('first-control').hidden=selection.value.startsWith('lines');
  });
  document.querySelectorAll('[data-camera]').forEach(button=>button.addEventListener('click',()=>{
    const eyes={oblique:{x:1.7,y:1.5,z:1.15},top:{x:0,y:0,z:2.5},front:{x:0,y:-2.5,z:.001}};
    if(view.ready) {
      view.state.setCamera({eye:eyes[button.dataset.camera],center:{x:0,y:0,z:0},up:{x:0,y:button.dataset.camera==='top'?1:0,z:button.dataset.camera==='top'?0:1},projection:{type:'orthographic'}});
      view.draw('view');publish();
    }
  }));
  const closest=document.getElementById('closest');
  if(closest) closest.addEventListener('click',()=>{first.value=1/3;second.value=-1/3;view.draw();});
  matchMedia('(prefers-color-scheme:dark)').addEventListener('change',update);
  window.addEventListener('message',event=>{
    if(event.source!==parent)return;
    if(event.data?.type==='math-preview-init'){
      const saved=event.data.state;GeometryRuntime.restore(view.state,saved);
      if(saved){
        if(saved.selection&&[...selection.options].some(option=>option.value===saved.selection))selection.value=saved.selection;
        extentInput.value=view.state.renderRadius;
        for(const [input,key] of [[first,'first'],[second,'second'],[axis,'axis']])if(input&&saved[key]!==undefined){
          if(input.type==='range'){input.min=Math.min(Number(input.min),-view.state.renderRadius,Number(saved[key]));input.max=Math.max(Number(input.max),view.state.renderRadius,Number(saved[key]));}
          input.value=saved[key];
        }
        if(saved.showPlane!==undefined&&document.getElementById('show-plane'))document.getElementById('show-plane').checked=saved.showPlane;
        if(saved.plotHeight)space.style.height=saved.plotHeight;
      }
      active=!!event.data.visible;view.draw();return;
    }
    if(event.data?.type==='math-preview-suspend'){active=false;view.scheduler.cancel();publish();return;}
    if(event.data?.type==='math-preview-visibility'){
      const previous=active;active=!!event.data.visible;
      if(active&&!previous)view.draw();else if(!active){view.scheduler.cancel();publish();}
    }
  });
  if(window!==parent)parent.postMessage({type:'math-preview-ready'},'*');else view.draw();
})();
