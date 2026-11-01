(function(root) {
  'use strict';
  function identity(current, article) {
    return current && typeof current.source === 'string' && article && article.getAttribute('aria-busy') !== 'true' ? current.kind + ':' + current.path : '';
  }

  function course(current, article, title) {
    const id = identity(current, article);
    if (!id || !article) return null;
    const text = ReaderSelectionCopy.selectionMarkdown(article);
    const item=typeof ReaderStudyQuestions!=='undefined'?ReaderStudyQuestions.selected(article,current.questions||[]):null;
    let prefix='',suffix='';
    const selection=article.ownerDocument.getSelection();
    if(selection?.rangeCount&&root.ReaderTextMap){
      const range=selection.getRangeAt(0);
      for(const run of root.ReaderTextMap.collect(article)){
        const start=run.nodes.find(n=>n.node===range.startContainer),end=run.nodes.find(n=>n.node===range.endContainer);
        if(start&&end){prefix=run.text.slice(Math.max(0,start.start+range.startOffset-60),start.start+range.startOffset);suffix=run.text.slice(end.start+range.endOffset,end.start+range.endOffset+60);break;}
      }
    }
    return text?.trim() ? {identity:id,text,title,document:current.source,question:item?.question||text,anchor:item?.anchor||'',prefix,suffix} : null;
  }

  function webpage(document) {
    const selection = document.getSelection();
    const body = document.body;
    if (!body || !selection?.rangeCount || selection.isCollapsed) return null;
    const range = selection.getRangeAt(0);
    if (!body.contains(range.startContainer) || !body.contains(range.endContainer)) return null;
    if (document.activeElement?.matches('input,textarea,select,[contenteditable="true"]')) return null;
    const text = selection.toString();
    if (!text.trim()) return null;
    const content = body.cloneNode(true);
    content.querySelectorAll('[data-math-source]').forEach(node => node.replaceWith(document.createTextNode(node.dataset.mathSource)));
    content.querySelectorAll('annotation[encoding="application/x-tex"]').forEach(node => {
      const formula = node.closest('.katex') || node.closest('math');
      if (formula) formula.replaceWith(document.createTextNode('$' + node.textContent + '$'));
    });
    content.querySelectorAll('script[type^="math/tex"]').forEach(node => {
      const block = node.type.includes('mode=display');
      node.replaceWith(document.createTextNode(block ? '\n$$\n' + node.textContent + '\n$$\n' : '$' + node.textContent + '$'));
    });
    content.querySelectorAll('script,style,noscript,iframe,canvas,svg,input,textarea,select,button,[hidden],[aria-hidden="true"]').forEach(node => node.remove());
    content.querySelectorAll('p,div,section,article,h1,h2,h3,h4,h5,h6,li,blockquote,pre,br,tr').forEach(node => { node.before('\n'); node.after('\n'); });
    content.querySelectorAll('td,th').forEach(node => node.append('\t'));
    return {identity:document.location.href, title:document.title, text, document:content.textContent};
  }

  function bindCourse(current, article, title) {
    let snapshot=null;
    function capture() {
      const owner=current();
      const value=course(owner,article,title());
      if (value) snapshot={owner,value};
      else if (!identity(owner,article) || snapshot?.owner !== owner) snapshot=null;
      return snapshot?.value || null;
    }
    article.ownerDocument.addEventListener('selectionchange',capture);
    return {material:capture,dispose(){article.ownerDocument.removeEventListener('selectionchange',capture);snapshot=null;}};
  }

  function bindWebpage(document) {
    let snapshot=null;
    function capture() {
      const value=webpage(document);
      if (value) {
        const range=document.getSelection().getRangeAt(0);
        snapshot={value,start:range.startContainer,end:range.endContainer};
      }
      if (snapshot && (snapshot.value.identity !== document.location.href || !snapshot.start.isConnected || !snapshot.end.isConnected)) snapshot=null;
      return snapshot?.value || null;
    }
    document.addEventListener('selectionchange',capture);
    return {material:capture,dispose(){document.removeEventListener('selectionchange',capture);snapshot=null;}};
  }

  root.ReaderExplanation = {identity, course, webpage, bindCourse, bindWebpage};
})(window);
