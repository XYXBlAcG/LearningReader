(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  else root.ReaderCourseContext=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  const globalKeys=new Set(['reader_zoom','reader_outline_width']);
  function normalize(value){
    const parts=[];
    for(const part of value.split('/')){
      if(!part||part==='.')continue;
      if(part==='..'){if(!parts.length)return null;parts.pop();}else parts.push(part);
    }
    return parts.join('/');
  }
  function resolve(value,active,files){
    const path=value.split('#')[0];
    const paths=[path,normalize((active?.path.split('/').slice(0,-1).join('/')||'')+'/'+path)];
    for(const candidate of paths){
      if(!candidate)continue;
      for(const [kind,list] of [['note',files.notes],['exercise',files.exercises]]){
        if((list||[]).some(item=>item.path===candidate))return {kind,path:candidate};
      }
    }
    return null;
  }
  function storage(raw,source,legacy=false,seed={}){
    const prefix='course:'+source+':';
    if(legacy&&raw.getItem(prefix+'migrated')===null){
      for(const [key,value] of Object.entries(seed))if(key.startsWith('reader_')&&raw.getItem(key)===null)raw.setItem(key,value);
      const roots={note:'数学笔记/',exercise:'数学练习/'};
      const transform=value=>{
        if(Array.isArray(value))return value.map(transform);
        if(value&&typeof value==='object'){
          const output=Object.fromEntries(Object.entries(value).map(([k,v])=>[k,transform(v)]));
          if(roots[output.kind]&&typeof output.path==='string'&&!output.path.startsWith(roots[output.kind]))output.path=roots[output.kind]+output.path;
          return output;
        }
        if(typeof value==='string')for(const [kind,root] of Object.entries(roots)){
          if(value.startsWith(kind+':')&&!value.startsWith(kind+':'+root))return kind+':'+root+value.slice(kind.length+1);
        }
        return value;
      };
      const keys=Array.from({length:raw.length},(_,i)=>raw.key(i)).filter(k=>k?.startsWith('reader_')&&!globalKeys.has(k));
      for(const key of keys){
        let target=key;
        for(const [kind,root] of Object.entries(roots))if(key.startsWith('reader_scroll:'+kind+':'))target='reader_scroll:'+kind+':'+root+key.slice(('reader_scroll:'+kind+':').length);
        const value=raw.getItem(key);
        let converted=value;
        try{converted=JSON.stringify(transform(JSON.parse(value)));}catch{}
        if(raw.getItem(prefix+target)===null)raw.setItem(prefix+target,converted);
      }
      raw.setItem(prefix+'migrated','1');
    }
    const key=value=>globalKeys.has(value)?value:prefix+value;
    return {getItem:k=>raw.getItem(key(k)),setItem:(k,v)=>raw.setItem(key(k),v),removeItem:k=>raw.removeItem(key(k))};
  }
  return {normalize,resolve,storage};
});
