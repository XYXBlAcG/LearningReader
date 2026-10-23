(function(root) {
  'use strict';
  class GeometryCache {
    constructor(limit=4){this.limit=limit;this.entries=new Map();}
    get(key,create) {
      if(this.entries.has(key)){const value=this.entries.get(key);this.entries.delete(key);this.entries.set(key,value);return value;}
      const value=create();this.entries.set(key,value);
      if(this.entries.size>this.limit)this.entries.delete(this.entries.keys().next().value);
      return value;
    }
  }
  class GeometryScheduler {
    constructor(draw){this.draw=draw;this.frame=0;this.busy=false;this.pending=new Set();}
    request(reason='view') {
      this.pending.add(reason);this.schedule();
    }
    schedule() {
      if(this.frame||this.busy||!this.pending.size)return;
      this.frame=requestAnimationFrame(async()=>{
        this.frame=0;const reason=this.pending.values().next().value;this.pending.delete(reason);this.busy=true;
        try{await this.draw(reason);}finally{this.busy=false;this.schedule();}
      });
    }
    cancel(){cancelAnimationFrame(this.frame);this.frame=0;this.pending.clear();}
  }
  function snapshot(state,extra={}) {
    return {displayRadius:state.displayRadius,renderRadius:state.renderRadius,camera:structuredClone(state.camera),sectionX:[...state.sectionX],sectionY:[...state.sectionY],...extra};
  }
  function restore(state,saved) {
    if(!saved)return;
    for(const key of ['displayRadius','renderRadius'])if(Number.isFinite(saved[key])&&saved[key]>0)state[key]=saved[key];
    if(saved.camera?.eye)state.setCamera(saved.camera);
    for(const key of ['sectionX','sectionY'])if(Array.isArray(saved[key])&&saved[key].length===2&&saved[key].every(Number.isFinite))state[key]=[...saved[key]];
  }
  root.GeometryRuntime={GeometryCache,GeometryScheduler,snapshot,restore};
})(window);
