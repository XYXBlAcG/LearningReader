(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  else root.ReaderPreviewPreference=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  function previewEnabled(choice,narrow){
    return choice==='true'||(choice!=='false'&&!narrow);
  }
  return {previewEnabled};
});
