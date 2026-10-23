(function(root,factory) {
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  else root.GeometryTraces=api;
})(typeof globalThis==='object'?globalThis:this,function() {
  'use strict';
  function line(points,name,color,width=5,dash='solid') {
    return {type:'scatter3d',mode:points.length===1?'markers':'lines',x:points.map(p=>p[0]),y:points.map(p=>p[1]),z:points.map(p=>p[2]),name,line:{color,width,dash},marker:{color,size:5},hovertemplate:name+'<br>(%{x:.2f}, %{y:.2f}, %{z:.2f})<extra></extra>'};
  }
  function surface(points,name,color,opacity=.38) {
    return {type:'surface',x:points.map(row=>row.map(p=>p[0])),y:points.map(row=>row.map(p=>p[1])),z:points.map(row=>row.map(p=>p[2])),colorscale:[[0,color],[1,color]],showscale:false,opacity,name,showlegend:false,hoverinfo:'skip',lighting:{ambient:.8,diffuse:.6,roughness:.8}};
  }
  return {line,surface};
});
