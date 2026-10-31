(function(root){
'use strict';
function locate(article,quote){
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
 const start=text.indexOf(quote);if(start<0||text.indexOf(quote,start+1)>=0)return null;
 const first=points[start],last=points[start+quote.length-1];if(!first||!last)return null;
 const range=article.ownerDocument.createRange();range.setStart(first.node,first.offset);range.setEnd(last.node,last.offset+1);return range;
}
let highlighted=[];
function mount(article,records,onOpen){
 highlighted=[];
 if(!root.CSS?.highlights||!root.Highlight)return;
 for(const record of records){
  const container=article.ownerDocument.createElement('div');container.innerHTML=root.ReaderMarkdown.render(record.quote);
  const range=locate(article,container.textContent);if(range)highlighted.push({range,id:record.id});
 }
 root.CSS.highlights.set('saved-explanations',new root.Highlight(...highlighted.map(x=>x.range)));
 article.onclick=event=>{
  if(!root.getSelection()?.isCollapsed||event.target.closest('a,button,.glossary-term'))return;
  const caret=article.ownerDocument.caretRangeFromPoint?.(event.clientX,event.clientY);if(!caret)return;
  const found=highlighted.filter(x=>x.range.isPointInRange(caret.startContainer,caret.startOffset));
  if(found.length)onOpen(found.map(x=>x.id));
 };
}
root.ReaderAnnotations={locate,mount};
})(window);
