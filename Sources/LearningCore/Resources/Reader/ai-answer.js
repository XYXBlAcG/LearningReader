(function(root) {
  'use strict';
  let pending = null, rendering = false;
  ReaderSelectionCopy.bind(document.getElementById('article'));
  async function update(source) {
    pending = source;
    if (rendering) return;
    rendering = true;
    try {
      await MathJax.startup.promise;
      while (pending !== null) {
        const value = pending; pending = null;
        const article = document.getElementById('article');
        const following = window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 80;
        const position = window.scrollY;
        MathJax.typesetClear([article]);
        article.innerHTML = ReaderMarkdown.render(value);
        ReaderCodeBlocks.enhance(article);
        await MathJax.typesetPromise([article]);
        window.scrollTo(0, following ? document.documentElement.scrollHeight : position);
      }
    } finally { rendering = false; }
  }
  root.AIAnswer = {update};
})(window);
