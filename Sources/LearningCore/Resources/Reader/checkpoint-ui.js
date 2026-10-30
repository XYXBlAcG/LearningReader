(function(root){
  'use strict';
  class Session {
    constructor(question,channel){this.question=question;this.channel=channel;this.signature=ReaderCheckpoints.signature(question);this.pending=null;}
    get history(){return this.channel.state.attempts.filter(a=>a.questionID===this.question.id&&a.signature===this.signature);}
    get draft(){return this.channel.state.drafts.find(d=>d.questionID===this.question.id&&d.signature===this.signature);}
    get selected(){return this.draft?.selected||[];}
    get mode(){return this.draft?.mode||'editing';}
    status(){
      const first=this.history[0];
      if(first?.action==='reveal')return '已看解析 · 待独立变式确认';
      if(first?.correct){
        const peers=(this.channel.questions||[]).filter(q=>q.group===this.question.group);
        const confirmed=peers.length>1&&peers.every(q=>this.channel.state.attempts.find(a=>a.questionID===q.id&&a.signature===ReaderCheckpoints.signature(q))?.correct===true);
        return confirmed?'首次答对 · 本组变式已通过':'首次答对 · 变式待确认';
      }
      if(first)return '需回看 · 首次未通过';
      if(this.channel.state.attempts.some(a=>a.questionID===this.question.id))return '题目已更新 · 待作答';
      return this.mode==='skipped'?'稍后再做':'未做';
    }
    async choose(selected){return this.edit(selected,'editing');}
    async edit(selected,mode){return this.channel.request({action:'draft',questionID:this.question.id,signature:this.signature,selected,mode});}
    async retry(){return this.edit([],'editing');}
    async skip(){return this.edit(this.selected,'skipped');}
    async submit(){ReaderCheckpoints.grade(this.question,this.selected);return this.record('submit');}
    async reveal(){return this.record('reveal');}
    async record(action){
      const key=JSON.stringify([action,this.selected]);
      if(this.pending?.key!==key){
        const bytes=root.crypto.getRandomValues(new Uint8Array(16));bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
        const hex=[...bytes].map(b=>b.toString(16).padStart(2,'0')).join('');
        this.pending={key,id:[hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-')};
      }
      const result=await this.channel.request({action,questionID:this.question.id,signature:this.signature,selected:this.selected,eventID:this.pending.id});
      this.pending=null;return result;
    }
  }

  async function mount(article,{courseID,typeset=()=>Promise.resolve()}={}){
    const boxes=[...article.querySelectorAll('[data-checkpoint]')];
    if(!boxes.length)return {dispose(){}};
    const questions=boxes.map(box=>JSON.parse(box.dataset.checkpoint)),store=new ReaderCheckpointStore.Store(courseID,questions);
    let disposed=false,queue=Promise.resolve();
    let initial;
    try{initial=await store.request({action:'load'});}catch(error){store.close();throw error;}
    const channel={questions,state:initial,request(command){
      const task=queue.then(()=>store.request(command)).then(state=>{channel.state=state;return state;});
      queue=task.catch(()=>{});return task;
    }};
    const document=article.ownerDocument,views=[];
    const summary=document.createElement('details');summary.className='checkpoint-summary';summary.dataset.copyIgnore='';
    const title=document.createElement('summary'),links=document.createElement('div');summary.append(title,links);article.prepend(summary);
    const html=text=>ReaderMarkdown.render(text,value=>value,false);
    function updateSummary(){
      const attempted=views.filter(v=>v.session.history.some(a=>a.action==='submit')).length;title.textContent='本节自测 · '+attempted+'/'+views.length+' 已作答';
      links.replaceChildren();
      for(const view of views){
        const a=document.createElement('a');a.href='#'+view.box.id;a.textContent=view.session.question.concept+' · '+view.session.status();links.append(a);
      }
    }
    for(const [index,box] of boxes.entries()){
      const q=questions[index],session=new Session(q,channel);
      const label=document.createElement('p');label.className='checkpoint-label';label.textContent='随堂自测 '+(index+1)+' · '+(q.type==='single'?'单选':'多选，选出全部正确项');
      const status=document.createElement('p');status.className='checkpoint-status';status.setAttribute('role','status');status.setAttribute('aria-live','polite');status.dataset.copyIgnore='';
      const stem=box.querySelector('.checkpoint-stem'),fieldset=document.createElement('fieldset');fieldset.setAttribute('aria-label',q.concept);
      const inputs=[];
      for(const [i,option] of q.options.entries()){
        const row=document.createElement('label');row.className='checkpoint-option';
        const input=document.createElement('input');input.type=q.type==='single'?'radio':'checkbox';input.name=q.id;input.value=option.id;
        const text=document.createElement('div');text.innerHTML=html(String.fromCharCode(65+i)+'. '+option.text);
        row.append(input,text);fieldset.append(row);inputs.push(input);
      }
      const controls=document.createElement('div');controls.className='checkpoint-actions';controls.dataset.copyIgnore='';
      const feedback=document.createElement('div');feedback.className='checkpoint-feedback';feedback.hidden=true;
      const error=document.createElement('p');error.className='checkpoint-error';error.setAttribute('role','alert');error.dataset.copyIgnore='';
      box.replaceChildren(label,stem,fieldset,status,controls,feedback,error);
      const buttons={};
      for(const [action,text] of [['submit','提交'],['reveal','查看解析'],['skip','稍后再做'],['retry','重新作答']]){
        const b=document.createElement('button');b.type='button';b.className='chip-btn';b.textContent=text;buttons[action]=b;controls.append(b);
      }
      let busy=false,feedbackKey='';
      async function run(operation){
        if(busy||disposed)return;busy=true;error.textContent='';refresh();
        try{await operation();if(!disposed)for(const view of views)view.refresh();}
        catch(issue){if(!disposed)error.textContent='未能保存：'+issue.message;}
        finally{busy=false;if(!disposed){refresh();updateSummary();}}
      }
      inputs.forEach(input=>input.addEventListener('change',()=>run(()=>session.choose(inputs.filter(i=>i.checked).map(i=>i.value)))));
      for(const action of ['submit','reveal','skip','retry'])buttons[action].addEventListener('click',()=>run(()=>session[action]()));
      function refresh(){
        const mode=session.mode;status.textContent=session.status();
        inputs.forEach(i=>{if(!busy)i.checked=session.selected.includes(i.value);i.disabled=busy||mode!=='editing';});
        fieldset.hidden=mode==='skipped';
        buttons.submit.hidden=buttons.reveal.hidden=buttons.skip.hidden=mode!=='editing';
        buttons.retry.hidden=mode==='editing';buttons.retry.textContent=mode==='skipped'?'继续作答':'重新作答';
        for(const b of Object.values(buttons))b.disabled=busy;
        buttons.submit.disabled=busy||!session.selected.length;
        feedback.hidden=mode!=='feedback';
        if(mode==='feedback'){
          const latest=session.history.at(-1),key=JSON.stringify(latest);
          if(key!==feedbackKey){
            feedbackKey=key;root.MathJax?.typesetClear?.([feedback]);feedback.replaceChildren();
            const result=document.createElement('p');
            if(latest?.action==='reveal')result.textContent='已查看解析，不计为独立答对。';
            else{
              const grade=ReaderCheckpoints.grade(q,session.selected),names=ids=>ids.map(id=>String.fromCharCode(65+q.options.findIndex(o=>o.id===id))).join('、');
              result.textContent=grade.correct?'✓ 本次选择正确':'✗ 本次选择未通过'+(grade.missing.length?' · 漏选 '+names(grade.missing):'')+(grade.extra.length?' · 误选 '+names(grade.extra):'');
            }
            feedback.append(result);
            q.options.forEach((o,i)=>{const part=document.createElement('div');part.innerHTML=html((q.correct.includes(o.id)?'**正确选项 ':'**非正确选项 ')+String.fromCharCode(65+i)+'：** '+o.feedback);feedback.append(part);});
            const explanation=document.createElement('div');explanation.innerHTML=html(q.explanation);feedback.append(explanation);
            const review=document.createElement('a');review.href=q.review;review.textContent='回看：'+q.concept;feedback.append(review);
            Promise.resolve(typeset()).catch(issue=>{if(!disposed)error.textContent='公式排版失败：'+issue.message;});
          }
        }else feedbackKey='';
      }
      views.push({box,session,refresh});refresh();
    }
    updateSummary();
    return {dispose(){disposed=true;queue.finally(()=>store.close());},sessions:views.map(v=>v.session)};
  }
  root.ReaderCheckpointUI={Session,mount};
})(window);
