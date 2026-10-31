(function(root) {
  'use strict';
  let glossaryView=null;
  let previous=null, pending = null, rendering = false, first=true, followOutput=true, initialPosition=0, scrollTimer;
  window.addEventListener('scroll',()=>{clearTimeout(scrollTimer);scrollTimer=setTimeout(()=>window.webkit?.messageHandlers?.studyPosition?.postMessage(window.scrollY),300);});
  ReaderSelectionCopy.bind(document.getElementById('article'));
  async function update(source,follow=true,position=0,glossary="",mode="off") {
    followOutput=follow;initialPosition=position;
    pending = source;
    if (rendering) return;
    rendering = true;
    try {
      await MathJax.startup.promise;
      while (pending !== null) {
        const value = pending; pending = null;
        if(value===previous)continue;
        const article = document.getElementById('article');
        const following = window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 80;
        const position = window.scrollY;
        glossaryView?.dispose();glossaryView=null;
        MathJax.typesetClear([article]);
        article.innerHTML = ReaderMarkdown.render(value);
        ReaderCodeBlocks.enhance(article);
        await MathJax.typesetPromise([article]);
        if(glossary){
          const library=JSON.parse(glossary);
          glossaryView=await ReaderGlossaryUI.mount(article,{library,mode,onPresent:ids=>window.webkit?.messageHandlers?.studyTerm?.postMessage(ids),typeset:nodes=>MathJax.typesetPromise(nodes),onNavigate:note=>window.webkit?.messageHandlers?.studyTerm?.postMessage({kind:note.kind,path:note.path,anchor:note.anchor})});
        }
        window.scrollTo(0,first?initialPosition:followOutput&&following?document.documentElement.scrollHeight:position);
        previous=value;first=false;
      }
    } finally { rendering = false; }
  }
  root.AIAnswer = {update};
})(window);
