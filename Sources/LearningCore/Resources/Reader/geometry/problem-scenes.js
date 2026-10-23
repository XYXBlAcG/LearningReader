(function(root, factory) {
  const api = factory(typeof module === 'object' && module.exports ? require('./models.js') : root.SpaceGeometry);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.ProblemScenes = api;
})(typeof globalThis === 'object' ? globalThis : this, function(G) {
  'use strict';
  const T = 2 * Math.PI;
  const n = G.scale([1,1,1], 1 / Math.sqrt(3));
  const e = G.scale([1,-1,0], 1 / Math.sqrt(2));
  const f = G.scale([1,1,-2], 1 / Math.sqrt(6));
  const S = p => p[0] + p[1] + p[2];
  const coneResidual = p => p[0]*p[1] + p[1]*p[2] + p[2]*p[0];
  const tilted = (h, radius, angle) => G.add(G.scale(n,h), G.add(G.scale(e,radius*Math.cos(angle)), G.scale(f,radius*Math.sin(angle))));
  const surface = (point, u, v, residual) => ({type:'surface', points:u.map(a => v.map(b => point(a,b))), residual});
  const curve = (point, values, residual) => ({type:'curve', points:values.map(point), residual});
  const line = (origin, direction, range, residual) => curve(t => G.add(origin,G.scale(direction,t)), [-range,range], residual);
  const layer = (key,name,color,geometry,extra={}) => ({key,name,color,geometry,...extra});
  const angles = () => G.sample(0,T,65);
  const band = r => G.sample(-r,r,33);
  const circle = (h,radius,residual) => curve(t => tilted(h,radius,t),angles(),residual);
  const tiltedPlane = (h,r) => surface((u,v) => G.add(G.scale(n,h), G.add(G.scale(e,u),G.scale(f,v))),[-r,r],[-r,r], p => S(p)-h*Math.sqrt(3));
  const axis = r => layer('axis','旋转轴 x=y=z','purple',[line([0,0,0],n,r)]);
  const diagCone = r => layer('surface','锥面 xy+yz+zx=0','blue',[surface((h,t) => tilted(h,Math.sqrt(2)*Math.abs(h),t),band(r),angles(),coneResidual)]);
  const sphere = radius => surface((v,u) => [radius*Math.sin(v)*Math.cos(u),radius*Math.sin(v)*Math.sin(u),radius*Math.cos(v)],G.sample(0,Math.PI,33),angles(),p=>G.dot(p,p)-radius*radius);
  const control = (key,label,value,min,max,step=.1) => ({key,label,value,min,max,step});
  const scene = (title,equation,layers,controls=[],description='图形只显示有限范围；母线图层展示代表性直线。') => ({title,equation,layers,controls,description});
  const controls = {h:control('h','切平面位置 h',0,-3,3),a:control('a','平面常数 a',1,-3,3)};
  const registry = {};

  registry['sphere-parameters'] = (p,r) => {
    const R=p.R ?? 2;
    return scene('球面的经线与纬线',String.raw`x^2+y^2+z^2=R^2,\quad R=${R}`,[
      layer('surface','球面','blue',[sphere(R)]),
      layer('latitude','纬线：固定高度','green',[-.6,0,.6].map(k=>curve(t=>[R*Math.sqrt(1-k*k)*Math.cos(t),R*Math.sqrt(1-k*k)*Math.sin(t),R*k],angles(),q=>G.dot(q,q)-R*R))),
      layer('longitude','经线：固定方位','orange',[0,Math.PI/3,2*Math.PI/3].map(u=>curve(v=>[R*Math.sin(v)*Math.cos(u),R*Math.sin(v)*Math.sin(u),R*Math.cos(v)],G.sample(0,T,97),q=>G.dot(q,q)-R*R)))
    ],[control('R','球半径 R',2,.5,3)]);
  };
  registry['slanted-cylinder'] = (p,r) => {
    const h=p.h??0;
    const residual=q=>(q[0]-q[2])**2+q[1]**2-1;
    const point=(v,u)=>[Math.cos(u)+v,Math.sin(u),v];
    return scene('斜柱面的准线与母线',String.raw`(x-z)^2+y^2=1`,[
      layer('surface','斜柱面','blue',[surface(point,band(r),angles(),residual)]),
      layer('directrix','准线：z=0 的圆','orange',[curve(u=>point(0,u),angles(),residual)]),
      layer('generators','母线：方向 (1,0,1)','purple',G.sample(0,T,9).map(u=>curve(v=>point(v,u),[-r,r],residual))),
      layer('section','固定 y='+h+' 的截痕','green',G.section(G.quadrics.cylinder,1,h,r).curves.map(points=>({type:'curve',points,residual})))
    ],[control('h','切片位置 y',0,-2,2)]);
  };
  registry['sphere-projection'] = (p,r) => {
    const q=t=>[Math.sqrt(2)*Math.cos(t),2*Math.sin(t),Math.sqrt(2)*Math.cos(t)];
    return scene('空间曲线与投影柱面',String.raw`x^2+y^2+z^2=4,\quad z=x,\quad 2x^2+y^2=4`,[
      layer('surface','投影柱面','blue',[surface((z,t)=>[Math.sqrt(2)*Math.cos(t),2*Math.sin(t),z],band(r),angles(),p=>2*p[0]**2+p[1]**2-4)]),
      layer('sphere','原球面','gray',[sphere(2)],{visible:false}),
      layer('source','原空间曲线','orange',[curve(q,angles(),p=>G.dot(p,p)-4)]),
      layer('projection','投影椭圆：z=0','green',[curve(t=>{const a=q(t);return[a[0],a[1],0];},angles(),p=>2*p[0]**2+p[1]**2-4)]),
      layer('drops','垂直投影线','gray',G.sample(0,T,9).map(t=>({type:'curve',points:[q(t),[q(t)[0],q(t)[1],0]]})),{dash:true})
    ]);
  };
  registry['unit-cone'] = (p,r) => {
    const residual=q=>q[0]**2+q[1]**2-q[2]**2;
    const point=(z,t)=>[z*Math.cos(t),z*Math.sin(t),z];
    return scene('圆锥：完整母线延伸到两侧',String.raw`x^2+y^2=z^2`,[
      layer('surface','双侧圆锥','blue',[surface(point,band(r),angles(),residual)]),
      layer('directrix','准线：z=1 的单位圆','orange',[curve(t=>point(1,t),angles(),residual)]),
      layer('generators','经过顶点的母线','purple',G.sample(0,T,9).map(t=>curve(z=>point(z,t),[-r,r],residual))),
      layer('vertex','顶点 O','green',[{type:'curve',points:[[0,0,0]]}])
    ]);
  };
  registry['elliptical-cone'] = (p,r) => {
    const a=p.a??2,b=p.b??1,c=p.c??1;
    const residual=q=>q[0]**2/(a*a)+q[1]**2/(b*b)-q[2]**2/(c*c);
    const point=(z,t)=>[a*z*Math.cos(t)/c,b*z*Math.sin(t)/c,z];
    return scene('椭圆准线生成锥面',String.raw`\frac{x^2}{a^2}+\frac{y^2}{b^2}=\frac{z^2}{c^2},\quad a=${a},\ b=${b},\ c=${c}`,[
      layer('surface','椭圆锥面','blue',[surface(point,band(r),angles(),residual)]),
      layer('directrix','准线：z=1','orange',[curve(t=>point(1,t),angles(),residual)]),
      layer('generators','母线','purple',G.sample(0,T,9).map(t=>curve(z=>point(z,t),[-r,r],residual)))
    ],[control('a','参数 a（正值示例）',2,.5,3),control('b','参数 b（正值示例）',1,.5,3),control('c','参数 c（正值示例）',1,.5,3)]);
  };
  registry['tilted-cone'] = (p,r) => scene('倾斜准线与圆锥',String.raw`xy+yz+zx=0,\quad \Gamma:x^2+y^2+z^2=1,\ x+y+z=1`,[
    diagCone(r),axis(r),layer('directrix','准线 Γ','orange',[circle(1/Math.sqrt(3),Math.sqrt(2/3),coneResidual)]),
    layer('plane','准线所在平面','gray',[tiltedPlane(1/Math.sqrt(3),r)],{visible:false}),
    layer('generators','母线','purple',G.sample(0,T,9).map(t=>line([0,0,0],tilted(1/Math.sqrt(3),Math.sqrt(2/3),t),r,coneResidual)))
  ]);
  registry['parabola-rotation'] = (p,r) => scene('半抛物线绕 z 轴生成曲面',String.raw`z=x^2+y^2`,[
    layer('surface','抛物面','blue',[surface((u,t)=>[u*Math.cos(t),u*Math.sin(t),u*u],G.sample(0,Math.sqrt(r),33),angles(),q=>q[2]-q[0]**2-q[1]**2)]),
    layer('source','原半抛物线','orange',[curve(u=>[u,0,u*u],G.sample(0,Math.sqrt(r),65))]),
    layer('circles','旋转轨迹（纬线）','green',[.5,1,1.5].filter(h=>h<=r).map(h=>curve(t=>[Math.sqrt(h)*Math.cos(t),Math.sqrt(h)*Math.sin(t),h],angles())))
  ]);
  for(const [id,model] of [['ellipsoid-sections','ellipsoid'],['single-sections','single'],['double-sections','double'],['bowl-sections','paraboloid'],['saddle-sections','saddle']]) {
    registry[id]=(p,r)=>{
      const h=p.h??0,m=G.quadrics[model],slice=G.section(m,2,h,r);
      const tex={ellipsoid:String.raw`\frac{x^2}{4}+\frac{y^2}{\frac{9}{4}}+\frac{z^2}{4}=1`,single:'x^2+y^2-z^2=1',double:'z^2-x^2-y^2=1',paraboloid:'z=x^2+y^2',saddle:'z=x^2-y^2'}[model];
      return scene(m.name+'与截痕',tex+String.raw`,\quad z=`+h,[
        layer('surface',m.name,'blue',G.surfacePatches(m,r).map(points=>({type:'surface',points,residual:q=>G.residual(m,q)}))),
        layer('plane','切割平面 z='+h,'orange',[surface((x,y)=>[x,y,h],[-r,r],[-r,r],q=>q[2]-h)]),
        layer('section','截痕：'+slice.kind,'green',slice.curves.map(points=>({type:'curve',points,residual:q=>G.residual(m,q)})))
      ],[controls.h], '绿色是当前截痕：'+slice.kind+'。空集时没有绿色曲线；相切时只标一个点。');
    };
  }
  registry['shifted-cone']=(p,r)=>{
    const residual=q=>q[0]**2+q[1]**2-(q[2]-2)**2;
    return scene('直线旋转形成双侧圆锥',String.raw`x^2+y^2=(z-2)^2`,[
      layer('surface','旋转曲面','blue',[surface((h,t)=>[h*Math.cos(t),h*Math.sin(t),2+h],band(r),angles(),residual)]),
      layer('source','原直线 y=0，z=x+2','orange',[curve(t=>[t,0,t+2],[-r,r],residual)]),
      layer('vertex','顶点 (0,0,2)','green',[{type:'curve',points:[[0,0,2]]}])
    ]);
  };
  registry['axis-line-cone']=(p,r)=>scene('x 轴绕斜轴旋转',String.raw`xy+yz+zx=0`,[diagCone(r),axis(r),layer('source','原直线：x 轴','orange',[line([0,0,0],[1,0,0],r,coneResidual)])]);
  registry['ruled-saddle']=(p,r)=>{
    const a=p.a??1,b=p.b??1;
    const residual=q=>q[0]**2/(a*a)-q[1]**2/(b*b)-2*q[2];
    return scene('马鞍面上的两族直线',String.raw`\frac{x^2}{a^2}-\frac{y^2}{b^2}=2z,\quad a=${a},\ b=${b}`,[
      layer('surface','双曲抛物面','blue',[surface((x,y)=>[a*x,b*y,(x*x-y*y)/2],band(r),band(r),residual)]),
      ...[1,-1].map((sign,index)=>layer('family-'+index,'第'+(index+1)+'族母线',index?'green':'orange',[-2,-1,0,1,2].map(u=>curve(v=>[a*(u+v)/2,sign*b*(u-v)/2,u*v/2],band(r),residual))))
    ],[control('a','参数 a',1,.5,3),control('b','参数 b',1,.5,3)]);
  };
  registry['ruled-hyperboloid']=(p,r)=>{
    const a=p.a??1,b=p.b??1,c=p.c??1;
    const residual=q=>q[0]**2/(a*a)+q[1]**2/(b*b)-q[2]**2/(c*c)-1;
    return scene('单叶双曲面上的两族直线',String.raw`\frac{x^2}{a^2}+\frac{y^2}{b^2}-\frac{z^2}{c^2}=1,\quad a=${a},\ b=${b},\ c=${c}`,[
      layer('surface','单叶双曲面','blue',G.surfacePatches(G.quadrics.single,r).map(points=>({type:'surface',points:points.map(row=>row.map(q=>[a*q[0],b*q[1],c*q[2]])),residual}))),
      ...[1,-1].map((s,index)=>layer('family-'+index,'第'+(index+1)+'族母线',index?'green':'orange',G.sample(0,T,13).map(u=>curve(v=>[a*(Math.cos(u)-s*v*Math.sin(u)),b*(Math.sin(u)+s*v*Math.cos(u)),c*v],band(r),residual))))
    ],[control('a','参数 a',1,.5,3),control('b','参数 b',1,.5,3),control('c','参数 c',1,.5,3)]);
  };
  registry['distance-cylinder']=(p,r)=>scene('与 z 轴距离为 2',String.raw`x^2+y^2=4`,[
    layer('surface','圆柱面','blue',[surface((z,t)=>[2*Math.cos(t),2*Math.sin(t),z],band(r),angles(),q=>q[0]**2+q[1]**2-4)]),
    layer('axis','z 轴','purple',[line([0,0,0],[0,0,1],r)]),layer('radius','垂直距离 2','orange',[{type:'curve',points:[[0,0,0],[2,0,0]]}])
  ]);
  registry['excluded-cone']=(p,r)=>{
    const residual=q=>q[0]**2-q[1]**2-(1-q[2])**2;
    const branch=(s,u)=>[s*Math.cosh(u),Math.sinh(u),0];
    return scene('生成锥面与消元多收的方向',String.raw`x^2-y^2=(1-z)^2`,[
      layer('surface','由准线有限点生成的锥面','blue',[1,-1].map(s=>surface((t,u)=>G.add([0,0,1],G.scale(G.add(branch(s,u),[0,0,-1]),t)),band(r),G.sample(-1.6,1.6,49),residual))),
      layer('directrix','准线：z=0 的双曲线','orange',[1,-1].map(s=>curve(u=>branch(s,u),G.sample(-1.6,1.6,97),residual))),
      layer('excluded','方程多收、原轨迹不包含（顶点除外）','red',[line([0,0,1],[1,1,0],r,residual),line([0,0,1],[1,-1,0],r,residual)],{dash:true})
    ],[],'红色虚线上的非顶点点不属于准线生成的精确轨迹。蓝色按生成参数采样，不跨接遗漏方向。');
  };
  registry['restricted-projection']=(p,r)=>{
    const intervals=[[0,Math.PI/2],[Math.PI,3*Math.PI/2]];
    const projected=t=>{const co=Math.cos(t),si=Math.sin(t),k=3/Math.sqrt(1+co*si);return[k*co,k*si,0];};
    const source=(t,sign)=>{const a=projected(t);return[a[0],a[1],sign*Math.sqrt(Math.max(0,a[0]*a[1]))];};
    return scene('投影椭圆只保留可恢复高度的部分',String.raw`x^2+y^2+z^2=9,\ z^2=xy;\quad x^2+y^2+xy=9,\ xy\ge0`,[
      layer('sphere','球面（辅助）','blue',[sphere(3)],{visible:false}),
      layer('source','原空间曲线（上下分支）','orange',intervals.flatMap(([lo,hi])=>[1,-1].map(s=>curve(t=>source(t,s),G.sample(lo,hi,65),q=>G.dot(q,q)-9)))),
      layer('projection','实际投影：两段椭圆弧','green',intervals.map(([lo,hi])=>curve(projected,G.sample(lo,hi,65),q=>q[0]**2+q[1]**2+q[0]*q[1]-9)))
    ]);
  };
  registry['sphere-plane-circle']=(p,r)=>{
    const u=[2/Math.sqrt(5),-1/Math.sqrt(5),0],v=[2/(3*Math.sqrt(5)),4/(3*Math.sqrt(5)),-5/(3*Math.sqrt(5))],C=[1,2,2];
    return scene('球心垂足就是截圆圆心',String.raw`x^2+y^2+z^2=25,\quad x+2y+2z=9`,[
      layer('surface','球面','blue',[sphere(5)]),
      layer('plane','切割平面','gray',[surface((a,b)=>G.add(C,G.add(G.scale(u,a),G.scale(v,b))),[-r,r],[-r,r],q=>q[0]+2*q[1]+2*q[2]-9)]),
      layer('section','交圆：圆心 (1,2,2)，半径 4','green',[curve(t=>G.add(C,G.add(G.scale(u,4*Math.cos(t)),G.scale(v,4*Math.sin(t)))),angles(),q=>G.dot(q,q)-25)]),
      layer('normal','球心到圆心的垂线','orange',[{type:'curve',points:[[0,0,0],C]}])
    ]);
  };
  registry['homework-1']=(p,r)=>{
    const residual=q=>q[0]**2/4-q[2]**2;
    return scene('退化柱面：两平面的并集',String.raw`\frac{x^2}{4}-z^2=0`,[
      layer('surface','平面 x=2z','blue',[surface((y,z)=>[2*z,y,z],band(r),band(r),residual)]),
      layer('second','平面 x=-2z','green',[surface((y,z)=>[-2*z,y,z],band(r),band(r),residual)]),
      layer('directrix','准线：y=-3 的两条直线','orange',[1,-1].map(s=>curve(z=>[s*2*z,-3,z],[-r,r],residual))),
      layer('generators','平行 Oy 的母线','purple',[1,-1].flatMap(s=>[-1,1].map(z=>line([s*2*z,0,z],[0,1,0],r,residual))))
    ]);
  };
  registry['homework-7']=(p,r)=>scene('绕斜轴的等距离圆柱',String.raw`3(x^2+y^2+z^2)-(x+y+z)^2=1`,[
    layer('surface','给定半径的圆柱','blue',[surface((h,t)=>tilted(h,1/Math.sqrt(3),t),band(r),angles(),q=>3*G.dot(q,q)-S(q)**2-1)]),axis(r),
    layer('radius','垂直于轴的半径','orange',[{type:'curve',points:[[0,0,0],G.scale(e,1/Math.sqrt(3))]}])
  ]);
  registry['homework-10']=(p,r)=>{
    const V=[3,2,1];
    const residual=q=>{const [X,Y,Z]=G.add(q,G.scale(V,-1)),L=X-Y+Z;return 3*L*L-(3*X+4*Y-Z)*L+X*X+2*Y*Y-Z*Z;};
    const q=u=>[(4-u*u)/(2*u),u,u-(4-u*u)/(2*u)];
    const branches=[1,-1].map(sign=>G.sample(-2,2,65).map(t=>sign*Math.exp(t)));
    return scene('作业 10：准线生成与排除的母线',String.raw`F=3L^2-(3X+4Y-Z)L+X^2+2Y^2-Z^2=0,\quad L=X-Y+Z`,[
      layer('surface','精确轨迹：由准线有限点生成','blue',branches.map(values=>surface((t,u)=>G.add(V,G.scale(G.add(q(u),G.scale(V,-1)),t)),band(r),values,residual))),
      layer('directrix','准线 Γ：x-y+z=0','orange',branches.map(values=>curve(q,values,p=>p[0]**2+2*p[1]**2-p[2]**2-4))),
      layer('vertex','顶点 V=(3,2,1)','green',[{type:'curve',points:[V]}]),
      layer('excluded','不属于精确轨迹的极限母线（顶点除外）','red',[[-1,0,1],[-1,2,3]].map(d=>line(V,d,r,residual)),{dash:true})
    ],[],'X=x−3，Y=y−2，Z=z−1。红色虚线的非顶点点不属于原轨迹；显示它们是为了区别二次方程与精确生成点集。');
  };
  registry['homework-16']=(p,r)=>{
    const residual=q=>coneResidual(q)-S(q)+1;
    return scene('偏轴直线旋转得到单叶双曲面',String.raw`xy+yz+zx-x-y-z+1=0`,[
      layer('surface','绕斜轴的单叶双曲面','blue',[surface((h,t)=>tilted(h,Math.sqrt(2*(h-Math.sqrt(3)/2)**2+.5),t),band(r),angles(),residual)]),axis(r),
      layer('source','原直线 (1,0,t)','orange',[curve(t=>[1,0,t],[-r,r],residual)]),
      layer('waist','最细处的圆','green',[circle(Math.sqrt(3)/2,1/Math.sqrt(2),residual)])
    ]);
  };
  registry['homework-20']=(p,r)=>{
    const aroundY=p.aroundY??1;
    const point=aroundY?((u,t)=>[u*u*Math.sin(t)/2,u,u*u*Math.cos(t)/2]):((u,t)=>[u*Math.sin(t),u*Math.cos(t),u*u/2]);
    const residual=aroundY?(q=>q[0]**2+q[2]**2-q[1]**4/4):(q=>q[0]**2+q[1]**2-2*q[2]);
    return scene('同一抛物线，换旋转轴',aroundY?String.raw`x^2+z^2=\frac{y^4}{4}`:'x^2+y^2=2z',[
      layer('surface',aroundY?'绕 Oy：四次曲面':'绕 Oz：二次抛物面','blue',[surface(point,band(Math.sqrt(2*r)),angles(),residual)]),
      layer('source','原抛物线 x=0，y²=2z','orange',[curve(u=>[0,u,u*u/2],band(Math.sqrt(2*r)),residual)]),
      layer('axis','当前旋转轴','purple',[line([0,0,0],aroundY?[0,1,0]:[0,0,1],r)])
    ],[{...control('aroundY','旋转轴',1,0,1,1),choices:['Oz 轴','Oy 轴']}]);
  };
  registry['homework-23']=(p,r)=>scene('直线族生成抛物柱面',String.raw`y^2=4x`,[
    layer('surface','抛物柱面','blue',[surface((y,z)=>[y*y/4,y,z],band(r),band(r),q=>q[1]**2-4*q[0])]),
    layer('directrix','z=0 的抛物线','orange',[curve(y=>[y*y/4,y,0],band(r))]),
    layer('generators','平行 z 轴的直线族','green',[-2,-1,0,1,2].map(y=>line([y*y/4,y,0],[0,0,1],r)))
  ]);
  registry['homework-29']=(p,r)=>{
    const R=p.R??2;
    const q=(sign,branch,t)=>[sign*R*t,sign*R*(1-t),branch*R*Math.sqrt(Math.max(0,2*t*(1-t)))];
    return scene('空间曲线投影成两条线段',String.raw`x^2+y^2+z^2=r^2,\ z^2=2xy,\quad r=${R}`,[
      layer('sphere','辅助球面','blue',[sphere(R)],{visible:false}),
      layer('source','原曲线：上下两支','orange',[1,-1].flatMap(s=>[1,-1].map(b=>curve(t=>q(s,b,t),G.sample(0,1,97),p=>G.dot(p,p)-R*R)))),
      layer('projection','实际投影：两条线段','green',[1,-1].map(s=>curve(t=>[s*R*t,s*R*(1-t),0],[0,1]))),
      layer('drops','垂直投影线','gray',[1,-1].flatMap(s=>[.2,.5,.8].map(t=>({type:'curve',points:[q(s,1,t),[s*R*t,s*R*(1-t),0]]}))),{dash:true})
    ],[control('R','球半径 r',2,.5,3)]);
  };
  registry['homework-30']=(p,r)=>scene('锥面和平面相交为两条垂直直线',String.raw`xy+yz+zx=0,\quad 2x+2y-z=0`,[
    diagCone(r),layer('plane','平面 2x+2y-z=0','gray',[surface((x,y)=>[x,y,2*x+2*y],[-r,r],[-r,r],q=>2*q[0]+2*q[1]-q[2])]),
    layer('first','交线一：方向 (2,−1,2)','orange',[line([0,0,0],[2,-1,2],r/3,coneResidual)]),
    layer('second','交线二：方向 (−1,2,2)','green',[line([0,0,0],[-1,2,2],r/3,coneResidual)])
  ],[],'展示满足题设的一组参数 a=2，b=2，c=−1。两方向内积为 −2−2+4=0；一般情形的证明见左侧解答。');
  registry['cone-circle']=(p,r)=>{
    const a=p.a??1;
    const section=a===0?[{type:'curve',points:[[0,0,0]],residual:coneResidual}]:[circle(a/Math.sqrt(3),Math.abs(a)*Math.sqrt(2/3),coneResidual)];
    return scene('切斜锥面：圆或退化点',String.raw`xy+yz+zx=0,\quad x+y+z=`+a,[
      diagCone(r),layer('plane','平面 x+y+z='+a,'orange',[tiltedPlane(a/Math.sqrt(3),r)]),
      layer('section',a===0?'交集：只有原点':'交圆','green',section),
      layer('center','圆心（退化时为原点）','purple',[{type:'curve',points:[[a/3,a/3,a/3]]}])
    ],[controls.a]);
  };
  for (const [id,choices] of [['compare-hyperboloids',['single-sections','double-sections']],['compare-paraboloids',['bowl-sections','saddle-sections']]]) {
    registry[id]=(p,r)=>{
      const result=registry[choices[p.model??0]](p,r);
      result.controls.unshift({...control('model','曲面类型',0,0,1,1),choices:id==='compare-hyperboloids'?['单叶双曲面','双叶双曲面']:['椭圆抛物面（碗形）','双曲抛物面（马鞍形）']});
      return result;
    };
  }
  function build(id, parameters={}, radius=3) {
    if (!registry[id]) throw new Error('未知题目图形：'+id);
    if (!Number.isFinite(radius) || radius<=0) throw new RangeError('绘制范围必须为正数');
    const model=registry[id](parameters,radius);
    const stages=[
      {name:'观察已知对象',keys:['directrix','source','axis','vertex','normal','radius']},
      {name:'沿构造方向展开',keys:['generators','circles','latitude','longitude','family-0','family-1']},
      {name:'展开曲面',keys:model.layers.filter(layer=>layer.key!=='plane'&&layer.geometry.some(g=>g.type==='surface')).map(layer=>layer.key)},
      {name:'比较截痕与几何关系',keys:model.layers.map(layer=>layer.key)}
    ];
    const assigned=new Set();
    model.steps=stages.map(stage=>{
      const keys=stage.keys.filter(key=>model.layers.some(layer=>layer.key===key)&&!assigned.has(key));
      keys.forEach(key=>assigned.add(key));
      return {name:stage.name,keys,description:keys.map(key=>model.layers.find(layer=>layer.key===key).name).join('；')};
    }).filter(stage=>stage.keys.length);
    return model;
  }
  function atProgress(model,progress) {
    const value=Math.max(0,Math.min(model.steps.length,progress));
    const layers=[];
    model.steps.forEach((step,index)=>{
      const fraction=Math.min(1,Math.max(0,value-index));
      if(!fraction)return;
      for(const layer of model.layers.filter(layer=>step.keys.includes(layer.key))) {
        if(fraction===1) { layers.push(layer);continue; }
        const geometry=layer.geometry.slice(0,Math.max(1,Math.ceil(layer.geometry.length*fraction))).map(g=>{
          const points=g.type==='surface'
            ?g.points.map(row=>row.slice(0,Math.max(2,Math.ceil(row.length*fraction))))
            :g.points.slice(0,Math.max(g.points.length===1?1:2,Math.ceil(g.points.length*fraction)));
          return {...g,points};
        });
        layers.push({...layer,geometry});
      }
    });
    return model.layers.filter(layer=>layers.some(visible=>visible.key===layer.key)).map(layer=>layers.find(visible=>visible.key===layer.key));
  }
  return {registry,build,atProgress};
});
