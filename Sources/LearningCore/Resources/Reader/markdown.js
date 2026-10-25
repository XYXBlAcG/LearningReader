(function(root) {
  'use strict';
  const mathPattern = /\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\]|\\begin\{[\s\S]+?\\end\{[^}]+\}|\$[^$\n]+?\$|\\\([\s\S]+?\\\)/g;

  function render(source, transform = value => value) {
    const sources = [];
    const prefix = '⟦MATH' + Math.random().toString(36).slice(2) + ':';
    const protectedSource = source.replace(mathPattern, value => prefix + (sources.push(value) - 1) + '⟧');
    const html = marked.parse(transform(protectedSource), {gfm:true, breaks:false});
    const template = document.createElement('template'); template.innerHTML = html;
    const pattern = new RegExp(prefix + '(\\d+)⟧', 'g');
    const walker = document.createTreeWalker(template.content, NodeFilter.SHOW_TEXT);
    const texts = []; while (walker.nextNode()) texts.push(walker.currentNode);
    for (const node of texts) {
      const matches = [...node.data.matchAll(pattern)]; if (!matches.length) continue;
      const fragment = document.createDocumentFragment(); let offset = 0;
      for (const match of matches) {
        fragment.append(node.data.slice(offset, match.index));
        const value = sources[Number(match[1])] ?? '';
        fragment.append(node.parentElement?.closest('pre,code') ? document.createTextNode(value) : ReaderSelectionCopy.mathNode(value));
        offset = match.index + match[0].length;
      }
      fragment.append(node.data.slice(offset)); node.replaceWith(fragment);
    }
    for (const node of template.content.querySelectorAll('*')) for (const attribute of [...node.attributes]) {
      node.setAttribute(attribute.name, attribute.value.replace(pattern, (_, index) => sources[Number(index)] ?? ''));
    }
    return DOMPurify.sanitize(template.innerHTML, {FORBID_TAGS:['iframe','form','style'], FORBID_ATTR:['style']});
  }

  root.ReaderMarkdown = {render};
})(window);
