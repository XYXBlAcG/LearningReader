(function(root){
'use strict';
const excluded='a,pre,code,script,style,button,input,textarea,select,h1,h2,h3,h4,h5,h6,[data-copy-ignore],[data-math-source],mjx-container,[data-glossary-ignore]';
const blocks=new Set(['P','DIV','LI','TD','TH','BLOCKQUOTE','SECTION']);
function collect(article){
 const runs=[];let nodes=[],text='',total=0,start=0;
 const flush=()=>{if(text)runs.push({text,start,nodes});text='';nodes=[];start=total};
 function visit(node){
  if(node.nodeType===3){if(!text)start=total;nodes.push({node,start:text.length,end:text.length+node.data.length});text+=node.data;total+=node.data.length;return}
  if(node.nodeType!==1)return;
  if(node.matches(excluded)){flush();return}
  const block=blocks.has(node.tagName);if(block)flush();for(const child of node.childNodes)visit(child);if(block)flush();
 }
 visit(article);flush();return runs;
}
root.ReaderTextMap={excluded,collect};
})(typeof window==='undefined'?globalThis:window);
