import Mark from 'mark.js/dist/mark.js';
import {computePosition,autoUpdate,offset,flip,shift,size} from '@floating-ui/dom';

const excluded=window.ReaderTextMap.excluded;
export function ranges(article,matcher,once=false){
 const result=[],seen=new Set();
 for(const run of window.ReaderTextMap.collect(article))for(const match of matcher.find(run.text)){
  if(once&&match.ids.every(id=>seen.has(id)))continue;
  match.ids.forEach(id=>seen.add(id));result.push({...match,start:run.start+match.start});
 }
 return result;
}
export function renderTerm(term){
  const section=document.createElement('section');section.className='glossary-definition prose';
  const heading=document.createElement('h2');heading.textContent=term.term;
  const subject=document.createElement('small');subject.textContent=term.subject;
  const body=document.createElement('div');body.innerHTML=window.ReaderMarkdown.render(term.body,value=>value,false);
  section.append(heading,subject,body);
  return section;
}
export async function mount(article,{library,onNavigate,typeset=()=>Promise.resolve(),mode='once',onModeChange=null,onPresent=null,onPresentLibrary=null}){
  let alive=true,cleanupPosition=null,popup=null,libraryDialog=null,pointer=null,returnFocus=null;
  const terms=new Map(library.terms.map(term=>[term.id,term]));
  const matcher=window.ReaderGlossaryCore.createMatcher(library);
  const marker=new Mark(article);
  const close=(restore=true)=>{cleanupPosition?.();cleanupPosition=null;if(popup){window.MathJax?.typesetClear?.([popup]);popup.remove();popup=null;}if(restore&&returnFocus?.isConnected)returnFocus.focus({preventScroll:true});returnFocus=null;};
  const openTerm=async(ids,reference=null,keyboard=false)=>{
    if(onPresent){onPresent(ids);return;}
    close(false);if(!alive)return;returnFocus=keyboard?reference:null;
    const entries=ids.map(id=>terms.get(id)).filter(Boolean);if(!entries.length)return;
    const card=document.createElement('aside');card.className='glossary-card';card.setAttribute('role','dialog');card.setAttribute('aria-label','术语释义');card.dataset.copyIgnore='true';
    popup=card;
    const closeButton=document.createElement('button');closeButton.type='button';closeButton.className='glossary-close';closeButton.textContent='关闭';closeButton.onclick=close;
    card.append(closeButton);
    if(entries.length>1){
      const prompt=document.createElement('p');prompt.textContent='这个名称有多个含义，请选择：';card.append(prompt);
      for(const term of entries){const button=document.createElement('button');button.type='button';button.className='glossary-choice';button.textContent=term.term+' · '+term.subject;button.onclick=()=>openTerm([term.id],reference);card.append(button);}
    }else{
      const term=entries[0];card.append(renderTerm(term));
      if(term.notes.length){
        const title=document.createElement('h3');title.textContent='相关笔记';card.append(title);
        for(const note of term.notes){const button=document.createElement('button');button.type='button';button.className='glossary-choice';button.textContent=note.documentLabel+' · '+note.label;button.onclick=()=>{close();onNavigate?.(note);};card.append(button);}
      }
      if(term.related.length){
        const title=document.createElement('h3');title.textContent='相关术语';card.append(title);
        for(const id of term.related){const target=terms.get(id);if(!target)continue;const button=document.createElement('button');button.type='button';button.textContent=target.term;button.onclick=()=>openTerm([id],reference);card.append(button);}
      }
      const expand=document.createElement('button');expand.type='button';expand.textContent='展开阅读';expand.onclick=()=>{card.classList.toggle('glossary-expanded');};card.append(expand);
    }
    document.body.append(card);
    if(reference?.isConnected){
      const position=()=>computePosition(reference,card,{strategy:'fixed',placement:'bottom',middleware:[offset(8),flip(),shift({padding:10}),size({padding:10,apply:({availableHeight,elements})=>{elements.floating.style.maxHeight=Math.max(80,availableHeight)+'px';}})]}).then(({x,y})=>{if(popup===card&&!card.classList.contains('glossary-expanded'))Object.assign(card.style,{left:x+'px',top:y+'px'});});
      cleanupPosition=autoUpdate(reference,card,position,{elementResize:typeof ResizeObserver!=='undefined',layoutShift:typeof IntersectionObserver!=='undefined'});
    }else card.classList.add('glossary-expanded');
    await typeset([card]);
    if(keyboard&&popup===card)closeButton.focus({preventScroll:true});
  };
  const activate=event=>{
    const target=event.target.closest('.glossary-term');
    if(!target||!article.contains(target)||!window.getSelection()?.isCollapsed)return;
    if(event.type==='keydown'&&!['Enter',' '].includes(event.key))return;
    if(event.type==='click'&&pointer&&Math.hypot(event.clientX-pointer.x,event.clientY-pointer.y)>8)return;
    event.preventDefault();event.stopPropagation();openTerm(JSON.parse(target.dataset.termIds),target,event.type==='keydown');
  };
  const down=event=>{pointer={x:event.clientX,y:event.clientY};};
  const outside=event=>{if(popup&&!popup.contains(event.target)&&!event.target.closest('.glossary-term'))close();};
  const escape=event=>{if(event.key==='Escape')close();};
  article.addEventListener('click',activate);article.addEventListener('keydown',activate);article.addEventListener('pointerdown',down);
  document.addEventListener('pointerdown',outside);document.addEventListener('keydown',escape);
  if(mode!=='off')await new Promise(resolve=>{
    const first=new Set();
    marker.markRanges(ranges(article,matcher,mode==='once'),{element:'span',className:'glossary-term',exclude:excluded.split(',').flatMap(selector=>[selector,selector+' *']),each:(node,range)=>{
      node.dataset.termIds=JSON.stringify(range.ids);node.setAttribute('role','button');node.setAttribute('aria-haspopup','dialog');
      node.tabIndex=first.has(range.start)?-1:0;first.add(range.start);
    },done:resolve});
  });
  return {openTerm,openLibrary(){
    if(onPresentLibrary){onPresentLibrary();return;}
    close();libraryDialog?.remove();
    const dialog=document.createElement('dialog');dialog.className='glossary-library';dialog.setAttribute('aria-label','课程术语库');libraryDialog=dialog;
    const heading=document.createElement('h2');heading.textContent='课程术语库';
    const closeButton=document.createElement('button');closeButton.textContent='关闭';closeButton.onclick=()=>dialog.close();
    const input=document.createElement('input');input.type='search';input.placeholder='搜索名称、别名或释义';input.setAttribute('aria-label','搜索术语');
    const subject=document.createElement('select');subject.setAttribute('aria-label','学科');
    for(const value of ['',...new Set(library.terms.map(term=>term.subject))]){const option=document.createElement('option');option.value=value;option.textContent=value||'全部学科';subject.append(option);}
    if(onModeChange){
      const settings=document.createElement('select');settings.setAttribute('aria-label','自动术语标注');
      for(const [value,label] of [['once','每篇首次'],['all','全部出现'],['off','关闭标注']]){const option=document.createElement('option');option.value=value;option.textContent=label;settings.append(option);}
      settings.value=mode;settings.onchange=()=>onModeChange(settings.value);dialog.append(settings);
    }
    const list=document.createElement('div');let limit=80;
    const render=()=>{
      list.replaceChildren();const query=input.value.trim().toLowerCase();
      const found=library.terms.filter(term=>(!subject.value||subject.value===term.subject)&&[term.term,...term.aliases,term.body].some(value=>value.toLowerCase().includes(query)));
      for(const term of found.slice(0,limit)){const button=document.createElement('button');button.type='button';button.className='glossary-choice';button.textContent=term.term+' · '+term.subject;button.onclick=()=>{dialog.close();openTerm([term.id]);};list.append(button);}
      if(!found.length)list.textContent=library.terms.length?'没有匹配的术语':'当前课程未提供术语文件夹';
      if(found.length>limit){const more=document.createElement('button');more.textContent='显示更多';more.onclick=()=>{limit+=80;render();};list.append(more);}
    };
    input.oninput=()=>{limit=80;render();};subject.onchange=()=>{limit=80;render();};
    dialog.prepend(heading,closeButton,input,subject);dialog.append(list);document.body.append(dialog);render();dialog.showModal();
  },dispose(){alive=false;close(false);libraryDialog?.remove();marker.unmark({className:'glossary-term'});article.removeEventListener('click',activate);article.removeEventListener('keydown',activate);article.removeEventListener('pointerdown',down);document.removeEventListener('pointerdown',outside);document.removeEventListener('keydown',escape);}};
}
