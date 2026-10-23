(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports) module.exports=api;
  else Object.assign(root,api);
})(typeof globalThis==='object'?globalThis:this,function(){
  'use strict';
  const initialCamera=()=>({eye:{x:1.7,y:1.5,z:1.15},center:{x:0,y:0,z:0},up:{x:0,y:0,z:1},projection:{type:'orthographic'}});
  class GeometryViewState {
    constructor(){
      this.displayRadius=3;
      this.renderRadius=3;
      this.camera=initialCamera();
      this.sectionX=[-3,3];
      this.sectionY=[-3,3];
    }
    zoom(factor){this.displayRadius*=factor;}
    setCamera(camera){this.camera=structuredClone(camera);}
    setRenderRadius(radius){
      if(!Number.isFinite(radius)||radius<=0) throw new RangeError('绘制范围必须为正数');
      this.renderRadius=radius;
    }
    fitDrawing(){
      this.displayRadius=this.renderRadius;
      this.sectionX=[-this.renderRadius,this.renderRadius];
      this.sectionY=[-this.renderRadius,this.renderRadius];
    }
    resetView(){
      this.displayRadius=3;
      this.camera=initialCamera();
      this.sectionX=[-3,3];
      this.sectionY=[-3,3];
    }
  }
  class GeometryPlayback {
    constructor(limit){this.limit=limit;this.progress=limit;this.playing=false;this.previousTime=null;}
    seek(value){this.pause();this.progress=Math.max(0,Math.min(this.limit,value));}
    play(){
      if(this.progress>=this.limit)this.progress=0;
      this.previousTime=null;this.playing=true;
    }
    pause(){this.playing=false;this.previousTime=null;}
    tick(time){
      if(!this.playing)return;
      const elapsed=this.previousTime===null?0:Math.max(0,Math.min(100,time-this.previousTime));
      this.previousTime=time;this.progress=Math.min(this.limit,this.progress+elapsed/2400);
      if(this.progress>=this.limit)this.pause();
    }
  }
  return {GeometryViewState,GeometryPlayback};
});
