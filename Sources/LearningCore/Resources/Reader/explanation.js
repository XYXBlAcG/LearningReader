(function(root) {
  'use strict';
  function identity(current, article) {
    return current && typeof current.source === 'string' && article && article.getAttribute('aria-busy') !== 'true' ? current.kind + ':' + current.path : '';
  }

  function course(current, article, title) {
    const id = identity(current, article);
    if (!id || !article) return null;
    const text = ReaderSelectionCopy.selectionMarkdown(article);
    return text?.trim() ? {identity:id, text, title, document:current.source} : null;
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

  root.ReaderExplanation = {identity, course, webpage};
})(window);
