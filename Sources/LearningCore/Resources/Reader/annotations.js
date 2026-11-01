(function(root){
'use strict';
function locate(article,quote,prefix="",suffix=""){
 if(!quote)return null;
 const normalize=value=>value.replace(/\s+/g,' ').trim();
 quote=normalize(quote);if(!quote)return null;
 const points=[];let text='';
 for(const run of root.ReaderTextMap.collect(article)){
  if(text&&!text.endsWith(' ')){text+=' ';points.push(null)}
  for(const item of run.nodes)for(let offset=0;offset<item.node.data.length;offset++){
   const character=item.node.data[offset];
   if(/\s/.test(character)){
    if(!text.endsWith(' ')){text+=' ';points.push({node:item.node,offset})}
   }else{text+=character;points.push({node:item.node,offset})}
  }
 }
 const candidates=[];prefix=normalize(prefix);suffix=normalize(suffix);
 let offset=text.indexOf(quote);
 while(offset>=0){
  const before=text.slice(0,offset).trimEnd(),after=text.slice(offset+quote.length).trimStart();
  if((!prefix||before.endsWith(prefix))&&(!suffix||after.startsWith(suffix)))candidates.push(offset);
  offset=text.indexOf(quote,offset+1);
 }
 if(candidates.length!==1)return null;const start=candidates[0];
 const first=points[start],last=points[start+quote.length-1];if(!first||!last)return null;
 const range=article.ownerDocument.createRange();range.setStart(first.node,first.offset);range.setEnd(last.node,last.offset+1);return range;
}
let highlighted=[],names=[];
function mount(article,records,onOpen){
 highlighted=[];const missing=[];
 if(!root.CSS?.highlights||!root.Highlight)return;
 for(const record of records){
  const container=article.ownerDocument.createElement('div');container.innerHTML=root.ReaderMarkdown.render(record.quote);
  const range=locate(article,container.textContent,record.prefix,record.suffix);if(range)highlighted.push({range,id:record.id,color:/^#[0-9a-f]{6}$/i.test(record.color||"")?record.color:"#FCE7A1",underline:record.underline==="true"});else missing.push(record.id);
 }
 for(const name of names)root.CSS.highlights.delete(name);names=[];
 const styles=[];
 for(const item of highlighted){
  const name='note-'+item.color.slice(1).toLowerCase()+(item.underline?'-line':'');
  if(names.includes(name))continue;names.push(name);
  root.CSS.highlights.set(name,new root.Highlight(...highlighted.filter(x=>x.color.toLowerCase()===item.color.toLowerCase()&&x.underline===item.underline).map(x=>x.range)));
  styles.push('::highlight('+name+'){'+(item.underline?'text-decoration:underline dotted '+item.color:'background-color:'+item.color+'55')+';color:inherit}');
 }
 let style=article.ownerDocument.getElementById('annotation-colors');if(!style){style=article.ownerDocument.createElement('style');style.id='annotation-colors';article.ownerDocument.head.append(style)}style.textContent=styles.join('\n');
 article.onclick=event=>{
  if(!root.getSelection()?.isCollapsed||event.target.closest('a,button,.glossary-term'))return;
  const caret=article.ownerDocument.caretRangeFromPoint?.(event.clientX,event.clientY);if(!caret)return;
  const found=highlighted.filter(x=>x.range.isPointInRange(caret.startContainer,caret.startOffset));
  if(found.length)onOpen(found.map(x=>x.id));
 };
 return missing;
}
root.ReaderAnnotations={locate,mount};
})(window);
