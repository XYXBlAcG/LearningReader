(function(root){
 'use strict';
 async function prepare(source,options={},resolve){
  const document=root.document,content=document.createElement('div'),body=document.createElement('section'),answers=document.createElement('section');
  content.innerHTML=ReaderMarkdown.render(source);
  const warnings=[],ancestors=[];let answerLevel=null,referenceCount=0;
  for(const node of [...content.children]){
   const level=/^H[1-6]$/.test(node.tagName)?Number(node.tagName[1]):null;
   if(level!==null&&answerLevel!==null&&level<=answerLevel)answerLevel=null;
   if(answerLevel===null&&level!==null){
    while(ancestors.length&&ancestors.at(-1).level>=level)ancestors.pop();
    if(ReaderExerciseCopy.isReferenceHeading(node)){
     for(const ancestor of ancestors.filter(item=>item.level>1))answers.append(ancestor.node.cloneNode(true));
     answerLevel=level;referenceCount++;
    }else ancestors.push({level,node});
   }
   (answerLevel!==null?answers:body).append(node);
  }
  if(!referenceCount)warnings.push('未找到明确的参考答案分区，请在预览中核对是否包含答案。');
  const blockSelector='p,div,section,blockquote,pre,table,ol,ul,h1,h2,h3,h4,h5,h6,img,figure,hr,[data-math-block="true"]';
  const nodes=[...body.children],ranges=ReaderExerciseCopy.questionRanges(nodes,false);
  for(const range of [...ranges].reverse()){
   const parent=nodes[range.listIndex],item=range.itemIndex===null?parent:[...parent.children].filter(n=>n.tagName==='LI')[range.itemIndex];
   const group=document.createElement(range.itemIndex===null?'section':'div');group.className='paper-question';
   if(range.itemIndex===null){item.before(group);group.append(item);}else{item.append(group);while(item.firstChild!==group)group.append(item.firstChild);}
   group.append(...nodes.slice(range.listIndex+1,range.endIndex));
   if(options.space==='medium'||options.space==='large'){
    group.dataset.space=options.space;
    const tail=document.createElement('div');tail.className='paper-tail';
    const last=[...group.childNodes].filter(node=>node.nodeType!==3||node.textContent.trim()).at(-1);
    if(last){
     const ending=[last];let previous=last.previousSibling;
     if(!(last.nodeType===1&&last.matches(blockSelector))){
      while(previous&&!(previous.nodeType===1&&previous.matches(blockSelector))){ending.unshift(previous);previous=previous.previousSibling;}
     }
     tail.append(...ending);
    }
    const space=document.createElement('div');space.className='paper-space';space.setAttribute('aria-hidden','true');
    tail.append(space);group.append(tail);
   }
  }
  if(!ranges.length)warnings.push('未识别到标准题号，已保留正文，请核对整套题是否完整。');
  const output=document.createElement('article');output.className='paper';output.append(body);
  if(options.answers&&referenceCount){answers.className='paper-answers';output.append(answers);}
  const images=new Map();
  for(const image of [...output.querySelectorAll('img')]){
   const src=image.getAttribute('src')||'';
   if(/\.html?(?:[?#]|$)/i.test(src)){
    const label=document.createElement('p');label.textContent='交互内容：'+(image.alt||src)+'（请在应用中查看）';image.replaceWith(label);
    warnings.push('交互网页无法打印，已保留文字提示。');continue;
   }
   try{
    if(!images.has(src))images.set(src,await ReaderStudyQuestions.imageData(src,resolve));
    image.src=images.get(src);
   }catch(error){throw new Error('题图导出失败：'+error.message);}
  }
  output.querySelectorAll('video,audio,iframe').forEach(node=>{const label=document.createElement('p');label.textContent='多媒体内容请在应用中查看。';node.replaceWith(label);warnings.push('多媒体内容无法打印。');});
  return {title:options.title||'练习试卷',html:output.outerHTML,questionCount:ranges.length,warnings:[...new Set(warnings)]};
 }
 async function render(payload){
  const article=document.getElementById('article');article.innerHTML=payload.html;
  await MathJax.startup.promise;await MathJax.typesetPromise([article]);
  if(article.querySelector('[data-mjx-error],mjx-merror,[data-mml-node="merror"]'))throw new Error('存在无法排版的公式，请核对原文。');
  await Promise.all([...article.querySelectorAll('img')].map(image=>image.decode()));
  await document.fonts.ready;
  return true;
 }
 root.ReaderPaper={prepare,render};
})(window);
