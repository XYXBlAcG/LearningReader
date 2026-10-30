import {Lexer,walkTokens} from 'marked';
import validateSchema from 'checkpoint-schema';

export function validate(question) {
  if(!validateSchema(question))throw new Error('自测字段不符合协议：'+JSON.stringify(validateSchema.errors));
  const ids=question.options.map(o=>o.id);
  if(new Set(ids).size!==ids.length)throw new Error('自测选项 ID 重复：'+question.id);
  if(question.correct.some(id=>!ids.includes(id)))throw new Error('正确答案引用了不存在的选项：'+question.id);
  if(question.type==='single'&&question.correct.length!==1)throw new Error('单选题必须只有一个正确选项：'+question.id);
  for(const value of [question.stem,question.explanation,...question.options.flatMap(o=>[o.text,o.feedback])]){
    walkTokens(Lexer.lex(value),token=>{if(token.type==='code'&&token.lang==='checkpoint')throw new Error('题目文字中不能嵌套自测：'+question.id);});
  }
  return question;
}

export function extract(source) {
  if(!source.includes('checkpoint'))return [];
  const tokens=Lexer.lex(source),top=new Set(tokens),found=[];
  walkTokens(tokens,token=>{if(token.type==='code'&&token.lang?.trim()==='checkpoint'&&!top.has(token))throw new Error('自测题块必须放在顶层段落之间');});
  let offset=0;
  for(const token of tokens){
    if(token.type==='code'&&token.lang?.trim()==='checkpoint'){
      let question;
      try{question=JSON.parse(token.text);}catch(error){throw new Error('自测 JSON 无法读取：'+error.message);}
      found.push({start:offset,end:offset+token.raw.length,question:validate(question)});
    }
    offset+=token.raw.length;
  }
  return found;
}

export function signature(q) {
  return JSON.stringify([q.revision,q.type,q.stem,q.options.map(o=>[o.id,o.text]).sort((a,b)=>a[0]<b[0]?-1:a[0]>b[0]?1:0),[...q.correct].sort()]);
}

export function grade(q,selected) {
  validate(q);
  if(!Array.isArray(selected)||!selected.length)throw new Error('请先选择选项');
  if(new Set(selected).size!==selected.length)throw new Error('不能重复选择同一选项');
  if(selected.some(id=>!q.options.some(o=>o.id===id)))throw new Error('选择了不存在的选项');
  if(q.type==='single'&&selected.length!==1)throw new Error('单选题只能选择一个选项');
  const missing=q.correct.filter(id=>!selected.includes(id)),extra=selected.filter(id=>!q.correct.includes(id));
  return {correct:!missing.length&&!extra.length,missing,extra};
}

export function headingID(text) {
  return text.replace(/!?\[([^\]]+)\]\([^)]*\)/g,'$1').replace(/[`*_~]/g,'').replace(/\$+/g,'').trim().toLowerCase().replace(/\s+/g,'-').replace(/[^a-z0-9\u4e00-\u9fff-]/g,'')||'section';
}

function reviewTarget(path,review) {
  if(/^[a-z]+:|^\/|\\/i.test(review))throw new Error('回看必须是课程内相对链接：'+review);
  const [file,rawAnchor='']=review.split('#');
  let anchor;
  try{anchor=decodeURIComponent(rawAnchor);}catch{throw new Error('回看链接编码无效');}
  const parts=file?path.split('/').slice(0,-1):path.split('/');
  if(file)for(const part of file.split('/')){if(part==='..'){if(!parts.length)throw new Error('回看链接越出课程');parts.pop();}else if(part&&part!=='.')parts.push(part);}
  return {path:parts.join('/'),anchor};
}

export function catalog(documents) {
  const ids=new Set(),targets=new Map(documents.map(doc=>[doc.path,doc])),headings=new Map(),items=[];
  for(const doc of documents){
    let blocks;
    try{blocks=extract(doc.source);}catch(error){throw new Error(doc.path+'：'+error.message);}
    for(const {question} of blocks){
      if(ids.has(question.id))throw new Error(doc.path+'：自测 ID 重复：'+question.id);
      ids.add(question.id);
      const target=reviewTarget(doc.path,question.review);
      if(target.anchor&&targets.has(target.path)&&!headings.has(target.path)){
        const anchors=new Set();
        for(const token of Lexer.lex(targets.get(target.path).source))if(token.type==='heading'){
          const base=headingID(token.text);let id=base,n=2;while(anchors.has(id))id=base+'-'+n++;anchors.add(id);
        }
        headings.set(target.path,anchors);
      }
      if(!targets.has(target.path)||(target.anchor&&!headings.get(target.path)?.has(target.anchor)))throw new Error(doc.path+'：回看目标不存在：'+question.review);
      items.push({kind:doc.kind,path:doc.path,question});
    }
  }
  return items;
}

export function project(source) {
  let result=source;
  for(const block of extract(source).reverse()){
    const q=block.question;
    result=result.slice(0,block.start)+'\n\n'+q.stem+'\n'+q.options.map(o=>'- '+o.text).join('\n')+'\n- 相关：[['+q.review+'|'+q.concept+']]\n\n'+result.slice(block.end);
  }
  return result;
}

export function requestJSON(input) {
  const request=JSON.parse(input);
  if(request.action==='catalog')return JSON.stringify(catalog(request.documents));
  if(request.action==='grade')return JSON.stringify(grade(request.question,request.selected));
  if(request.action==='signature')return JSON.stringify(signature(request.question));
  throw new Error('未知自测操作');
}
