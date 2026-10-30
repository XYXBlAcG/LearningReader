(function(root){
  'use strict';
  class Store {
    constructor(courseID,questions){this.courseID=courseID;this.questions=new Map(questions.map(q=>[q.id,q]));this.database=null;}
    async request(command){
      const native=root.webkit?.messageHandlers?.readerCheckpoint;
      if(native)return native.postMessage(command);
      if(!this.database)this.database=await new Promise((resolve,reject)=>{
        const opening=root.indexedDB.open('LearningReaderCheckpoints',1);
        opening.onupgradeneeded=()=>opening.result.createObjectStore('courses');
        opening.onsuccess=()=>resolve(opening.result);opening.onerror=()=>reject(opening.error);
        opening.onblocked=()=>reject(new Error('请关闭其他旧版课程页面后重试自测存储。'));
      });
      return new Promise((resolve,reject)=>{
        const transaction=this.database.transaction('courses',command.action==='load'?'readonly':'readwrite'),store=transaction.objectStore('courses');
        let result,issue;
        transaction.oncomplete=()=>resolve(result);transaction.onabort=()=>reject(issue||transaction.error||new Error('自测保存失败'));transaction.onerror=()=>reject(transaction.error);
        const reading=store.get(this.courseID);
        reading.onsuccess=()=>{
          try{
            result=reading.result||{attempts:[],drafts:[]};
            if(command.action==='load')return;
            const q=this.questions.get(command.questionID);
            if(!q||ReaderCheckpoints.signature(q)!==command.signature)throw new Error('自测版本已更新，请重新打开。');
            if(command.selected.length)ReaderCheckpoints.grade(q,command.selected);
            if(command.action==='submit'||command.action==='reveal'){
              if(!result.attempts.some(a=>a.id===command.eventID))result.attempts.push({id:command.eventID,questionID:q.id,signature:command.signature,selected:command.selected,action:command.action,correct:command.action==='submit'?ReaderCheckpoints.grade(q,command.selected).correct:null,date:Date.now()});
            }else if(command.action!=='draft')throw new Error('未知自测操作');
            result.drafts=result.drafts.filter(d=>d.questionID!==q.id||d.signature!==command.signature);
            result.drafts.push({questionID:q.id,signature:command.signature,selected:command.selected,mode:command.action==='draft'?command.mode:'feedback'});
            store.put(result,this.courseID);
          }catch(error){issue=error;transaction.abort();}
        };
      });
    }
    close(){this.database?.close();this.database=null;}
  }
  root.ReaderCheckpointStore={Store};
})(window);
