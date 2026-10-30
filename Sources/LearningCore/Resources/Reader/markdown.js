(function(root) {
  'use strict';
  const mathPattern = /\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\]|\\begin\{[\s\S]+?\\end\{[^}]+\}|\$[^$\n]+?\$|\\\([\s\S]+?\\\)/g;
  const parser = new marked.Marked({gfm:true,breaks:false}, ReaderCJK.default());

  function render(source, transform = value => value, checkpoints = true) {
    const blocks=checkpoints&&root.ReaderCheckpoints?root.ReaderCheckpoints.extract(source):[];
    const checkpointPrefix='CheckpointSlot'+Math.random().toString(36).slice(2);
    for(let index=blocks.length-1;index>=0;index--)source=source.slice(0,blocks[index].start)+'\n\n'+checkpointPrefix+index+'EndSlot\n\n'+source.slice(blocks[index].end);
    const sources = [];
    const prefix = 'MathSource' + Math.random().toString(36).slice(2) + 'Token';
    const protectedSource = source.replace(mathPattern, value => prefix + (sources.push(value) - 1) + 'EndMath');
    const html = parser.parse(transform(protectedSource));
    const template = document.createElement('template'); template.innerHTML = html;
    const pattern = new RegExp(prefix + '(\\d+)EndMath', 'g');
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
    for(const node of [...template.content.querySelectorAll('p')]){
      const match=node.textContent.match(new RegExp('^'+checkpointPrefix+'(\\d+)EndSlot$'));
      if(!match)continue;
      const q=blocks[Number(match[1])].question,box=document.createElement('section');
      box.className='checkpoint';box.id='checkpoint-'+q.id;box.dataset.checkpoint=JSON.stringify(q);
      const stem=document.createElement('div');stem.className='checkpoint-stem';stem.innerHTML=render(q.stem,value=>value,false);box.append(stem);
      const options=document.createElement('ol');options.type='A';
      for(const option of q.options){const li=document.createElement('li');li.innerHTML=render(option.text,value=>value,false);options.append(li);}
      box.append(options);node.replaceWith(box);
    }
    return DOMPurify.sanitize(template.innerHTML, {FORBID_TAGS:['iframe','form','style'], FORBID_ATTR:['style']});
  }

  root.ReaderMarkdown = {render};
})(window);
