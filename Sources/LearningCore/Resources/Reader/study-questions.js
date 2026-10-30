(function(root){
 'use strict';
 function build(article){
  const nodes=[...article.children];
  const reference=nodes.findIndex(ReaderExerciseCopy.isReferenceHeading);
  if(reference<0)return [];
  function entries(children,requireReference){
   const sections=[],stack=[];
   children.forEach((node,index)=>{
    if(/^H[2-6]$/.test(node.tagName)&&/^(?:第\s*)?\d+(?:\s*题|[.．、]|\s*$)/.test(node.textContent.trim())){const level=Number(node.tagName[1]);while(stack.length&&stack.at(-1).level>=level)stack.pop();}
    if(/^H[2-6]$/.test(node.tagName)&&!/^参考/.test(node.textContent.trim())&&!/^(?:第\s*)?\d+(?:\s*题|[.．、]|\s*$)/.test(node.textContent.trim())){
     const level=Number(node.tagName[1]);while(stack.length&&stack.at(-1).level>=level)stack.pop();
     if(!/^(题目|练习|答案)$/.test(node.textContent.trim()))stack.push({level,title:node.textContent.trim()});
    }
    sections[index]=stack.map(x=>x.title).join(' / ');
   });
   return ReaderExerciseCopy.questionRanges(children,requireReference).map(range=>{
    const parent=children[range.listIndex];
    const item=range.itemIndex===null?parent:[...parent.children].filter(n=>n.tagName==='LI')[range.itemIndex];
    const number=range.itemIndex===null?Number(item.textContent.match(/\d+/)?.[0]):Number(parent.getAttribute('start')||1)+range.itemIndex;
    const blocks=[item,...children.slice(range.listIndex+1,range.endIndex)];
    return {section:sections[range.listIndex],number,nodes:blocks,markdown:ReaderSelectionCopy.nodesMarkdown(blocks)};
   });
  }
  const answers=entries(nodes.slice(reference+1),false);
  const questions=entries(nodes,true);
  return questions.map((q,index)=>{
   const exact=answers.filter(a=>a.number===q.number&&a.section===q.section);
   const unique=answers.filter(a=>a.number===q.number);
   const duplicate=questions.filter(x=>x.number===q.number).length;
   const same=questions.filter(x=>x.section===q.section&&x.number===q.number).length;
   const answer=same===1&&exact.length===1?exact[0]:unique.length===1&&duplicate===1?unique[0]:null;
   const id='study-'+encodeURIComponent(q.section)+'-'+q.number+(questions.filter(x=>x.section===q.section&&x.number===q.number).length>1?'-'+index:'');
   q.nodes.forEach(n=>n.dataset.studyQuestion=id);
   const anchor=article.ownerDocument.createElement('span');anchor.id=id;anchor.setAttribute('data-copy-ignore','');q.nodes[0].prepend(anchor);
   if(answer)answer.nodes.forEach(n=>n.dataset.studyAnswer=id);
   return {id,label:[q.section,'第 '+q.number+' 题'].filter(Boolean).join(' · '),number:q.number,question:q.markdown,request:q.markdown,answer:answer?.markdown||'',anchor:id};
  });

 }
 function selected(article,items){
  const selection=article.ownerDocument.getSelection();if(!selection?.rangeCount||selection.isCollapsed)return null;
  const node=selection.getRangeAt(0).startContainer;
  const element=node.nodeType===1?node:node.parentElement;
  const owner=element?.closest('[data-study-question],[data-study-answer]');
  return items.find(x=>x.id===(owner?.dataset.studyQuestion||owner?.dataset.studyAnswer))||null;
 }
 async function imageData(src,resolve){
  if(src.startsWith('data:image/'))return src;
  const url=resolve(src);
  if(!url)throw new Error('资源未离线保存：'+src);
  const response=await fetch(url);if(!response.ok)throw new Error('无法读取 '+src+'（HTTP '+response.status+'）');
  const blob=await response.blob();if(!blob.type.startsWith('image/')||blob.size>12*1024*1024)throw new Error('图片格式或大小不受支持：'+src);
  return new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(reader.error);reader.readAsDataURL(blob);});
 }
 async function assets(markdown,resolve){
  const images=[];marked.walkTokens(marked.lexer(markdown),token=>{if(token.type==='image')images.push(token);});
  const replacements=new Map();
  for(const image of images){
   if(replacements.has(image.raw))continue;
   try{
    replacements.set(image.raw,'!['+image.text+']('+await imageData(image.href,resolve)+')');
   }catch(error){replacements.set(image.raw,'[图片未离线保存：'+image.text+'，'+error.message+']');}
  }
  for(const [raw,value] of replacements)markdown=markdown.split(raw).join(value);
  return markdown;
 }
 root.ReaderStudyQuestions={build,selected,assets,imageData};
})(window);
