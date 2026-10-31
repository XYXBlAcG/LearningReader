(function(root){
'use strict';
root.ReaderIOSPresentation={
 outlineTitle(heading){
  const copy=heading.cloneNode(true);copy.querySelectorAll('button,[data-copy-ignore]').forEach(node=>node.remove());return copy.textContent.trim();
 },
 reference(button,body,expanded){
  body.classList.toggle('open',expanded);body.previousElementSibling?.classList.toggle('open',expanded);
  button.textContent=expanded?'收起参考答案':'展开参考答案';button.setAttribute('aria-expanded',String(expanded));
 }
};
})(window);
