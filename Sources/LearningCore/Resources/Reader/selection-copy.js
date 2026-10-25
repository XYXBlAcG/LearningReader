(function(root) {
  'use strict';
  const converter=new TurndownService({headingStyle:'atx',codeBlockStyle:'fenced',bulletListMarker:'-',emDelimiter:'*'});
  const ignored='button, iframe, canvas, .interactive-embed, .code-toolbar, .preview-layout-controls, .preview-divider, .math-select-anchor, mjx-assistive-mml, [data-copy-ignore], [hidden]';
  converter.use(turndownPluginGfm.gfm);
  let mathSources=[];
  converter.addRule('originalMath',{
    filter:node=>node.hasAttribute('data-math-source'),
    replacement:(_,node)=>{
      const index=mathSources.push(node.dataset.mathSource)-1;
      const token='⟦COPYMATH'+index+'⟧';
      return node.dataset.mathBlock==='true'?'\n\n'+token+'\n\n':token;
    }
  });
  const mathParent=node=>(node.nodeType===1?node:node.parentElement)?.closest('[data-math-source]');

  function mathNode(source) {
    const block=source.startsWith('$$')||source.startsWith('\\[')||source.startsWith('\\begin');
    let markdown=source;
    if(source.startsWith('\\('))markdown='$'+source.slice(2,-2)+'$';
    else if(block)markdown='$$\n'+(source.startsWith('$$')||source.startsWith('\\[')?source.slice(2,-2):source).trim()+'\n$$';
    const node=document.createElement('span');node.className='math-source';
    node.dataset.mathSource=markdown;node.dataset.mathBlock=String(block);
    for(const part of ['\u200b',source,'\u200b']) {
      if(part===source)node.append(document.createTextNode(part));
      else {const anchor=document.createElement('span');anchor.className='math-select-anchor';anchor.setAttribute('aria-hidden','true');anchor.textContent=part;node.append(anchor);}
    }
    return node;
  }

  function selectionMarkdown(article) {
    const selection=article.ownerDocument.getSelection();
    if(!selection?.rangeCount||selection.isCollapsed)return null;
    const selected=selection.getRangeAt(0);
    if(!article.contains(selected.startContainer)||!article.contains(selected.endContainer))return null;
    const editable=article.ownerDocument.activeElement;
    if(editable?.matches('input,textarea,[contenteditable="true"]'))return null;
    const range=selected.cloneRange();
    const first=mathParent(range.startContainer),last=mathParent(range.endContainer);
    if(first)range.setStartBefore(first);
    if(last)range.setEndAfter(last);
    let content=range.cloneContents();
    const common=range.commonAncestorContainer;
    const ancestor=common.nodeType===1?common:common.parentElement;
    if(ancestor?.matches('h1,h2,h3,h4,h5,h6,p,strong,em,del,s,a,code,pre,blockquote,ol,ul,li')){
      const wrapper=ancestor.cloneNode(false);wrapper.append(content);content=document.createDocumentFragment();
      if(ancestor.tagName==='CODE'&&ancestor.parentElement?.tagName==='PRE'){
        const pre=ancestor.parentElement.cloneNode(false);pre.append(wrapper);content.append(pre);
      }else content.append(wrapper);
    }
    return contentMarkdown(content);
  }

  function elementMarkdown(element) {
    const content=document.createDocumentFragment();content.append(element.cloneNode(true));
    return contentMarkdown(content);
  }

  function contentMarkdown(content) {
    content.querySelectorAll('[data-math-source]').forEach(node=>node.replaceChildren(document.createTextNode(node.dataset.mathSource)));
    content.querySelectorAll(ignored).forEach(node=>node.remove());
    content.querySelectorAll('details:not([open])').forEach(node=>{
      for(const child of [...node.children])if(child.tagName!=='SUMMARY')child.remove();
    });
    content.querySelectorAll('summary').forEach(node=>{
      const paragraph=document.createElement('p');paragraph.append(...node.childNodes);node.replaceWith(paragraph);
    });
    content.querySelectorAll('.subquestion-label').forEach(node=>node.after(document.createTextNode(' ')));
    mathSources=[];
    return converter.turndown(content).replace(/⟦COPYMATH(\d+)⟧/g,(_,index)=>mathSources[Number(index)]).trim();
  }

  function bind(article) {
    article.ownerDocument.addEventListener('copy',event=>{
      if(event.defaultPrevented||!event.clipboardData)return;
      const markdown=selectionMarkdown(article);
      if(markdown===null||!markdown)return;
      event.clipboardData.setData('text/plain',markdown);
      event.preventDefault();
    });
    let pointer=null;
    article.addEventListener('pointerdown',event=>{
      const formula=event.target.closest('[data-math-source]');
      pointer=formula&&event.button===0?{formula,x:event.clientX,y:event.clientY}:null;
    });
    article.addEventListener('pointerup',event=>{
      if(pointer&&Math.hypot(event.clientX-pointer.x,event.clientY-pointer.y)<5&&!event.shiftKey){
        const range=document.createRange();range.selectNode(pointer.formula);
        const selection=document.getSelection();selection.removeAllRanges();selection.addRange(range);
      }
      pointer=null;
    });
  }
  root.ReaderSelectionCopy={bind,selectionMarkdown,elementMarkdown,mathNode};
})(window);
