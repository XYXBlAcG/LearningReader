(function(root) {
  'use strict';
  let previous=null, pending = null, rendering = false, first=true, followOutput=true, initialPosition=0, scrollTimer;
  window.addEventListener('scroll',()=>{clearTimeout(scrollTimer);scrollTimer=setTimeout(()=>window.webkit?.messageHandlers?.studyPosition?.postMessage(window.scrollY),300);});
  ReaderSelectionCopy.bind(document.getElementById('article'));
  async function update(source,follow=true,position=0) {
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
        MathJax.typesetClear([article]);
        article.innerHTML = ReaderMarkdown.render(value);
        ReaderCodeBlocks.enhance(article);
        await MathJax.typesetPromise([article]);
        window.scrollTo(0,first?initialPosition:followOutput&&following?document.documentElement.scrollHeight:position);
        previous=value;first=false;
      }
    } finally { rendering = false; }
  }
  root.AIAnswer = {update};
})(window);
