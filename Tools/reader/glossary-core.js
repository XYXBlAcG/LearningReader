import validate from 'glossary-schema';
import AhoCorasick from 'ahocorasick';
import ContentIndex from '../../Sources/LearningCore/Resources/Reader/content-index.js';

const fold=value=>value.replace(/[A-Z]/g,c=>c.toLowerCase());
const key=value=>value.kind+':'+value.path+'#'+value.anchor;
export function build(sources,documents){
  if(!sources.length)return {version:1,terms:[]};
  const sections=documents.flatMap(document=>ContentIndex.sections({...document,label:ContentIndex.title(document.path,document.source)}));
  const targets=new Map(documents.map(document=>[document.kind+':'+document.path,new Set(['',ContentIndex.headingId(ContentIndex.title(document.path,document.source)),...sections.filter(section=>section.kind===document.kind&&section.path===document.path).map(section=>section.anchor)])]));
  const terms=[],ids=new Set();
  for(const source of sources){
    const match=source.source.trim().match(/^# ([^\n]+)\r?\n+```glossary\r?\n([\s\S]*?)\r?\n```[ \t]*\r?\n([\s\S]*)$/);
    if(!match)throw new Error(source.path+'：缺少标题与 glossary 元数据块');
    let metadata;
    try{metadata=JSON.parse(match[2]);}catch{throw new Error(source.path+'：术语元数据 JSON 无效');}
    if(!validate(metadata))throw new Error(source.path+'：术语字段无效 '+JSON.stringify(validate.errors));
    if(metadata.term!==match[1].trim())throw new Error(source.path+'：标题必须与术语名一致');
    if(ids.has(metadata.id))throw new Error(source.path+'：术语 ID 重复 '+metadata.id);
    ids.add(metadata.id);
    const body=match[3].trim();
    for(const heading of ['直觉','定义','例子'])if(!new RegExp('^## '+heading+'[ \\t]*$','m').test(body))throw new Error(source.path+'：缺少 '+heading+' 小节');
    const notes=[];
    for(const note of metadata.notes){
      const anchors=targets.get(note.kind+':'+note.path);
      if(!anchors)throw new Error(source.path+'：笔记不存在 '+note.path);
      const anchor=anchors.has(note.anchor)?note.anchor:ContentIndex.headingId(note.anchor);
      if(!anchors.has(anchor))throw new Error(source.path+'：笔记锚点不存在 '+note.anchor);
      const section=sections.find(section=>section.kind===note.kind&&section.path===note.path&&section.anchor===anchor);
      notes.push({...note,anchor,label:section?.heading||note.path,documentLabel:section?.documentLabel||note.path});
    }
    const names=[metadata.term,...metadata.aliases];
    for(const section of sections){
      if(section.kind!=='note'||!names.some(name=>name.length>=2&&fold(section.heading).includes(fold(name))))continue;
      const note={kind:section.kind,path:section.path,anchor:section.anchor,label:section.heading,documentLabel:section.documentLabel};
      if(!notes.some(value=>key(value)===key(note)))notes.push(note);
    }
    terms.push({...metadata,notes:notes.slice(0,8),path:source.path,body});
  }
  for(const term of terms)for(const id of term.related)if(!ids.has(id))throw new Error(term.path+'：关联术语不存在 '+id);
  return {version:1,terms:terms.sort((a,b)=>a.id<b.id?-1:1)};
}
export function createMatcher(library){
  const aliases=new Map();
  for(const term of library.terms)for(const name of [term.term,...term.aliases]){
    if([...name].length<2)continue;
    const value=fold(name),ids=aliases.get(value)||[];
    if(!ids.includes(term.id))ids.push(term.id);
    aliases.set(value,ids);
  }
  const engine=aliases.size?new AhoCorasick([...aliases.keys()]):null;
  return {find(text){
    if(!engine)return [];
    const matches=[];
    for(const [end,names] of engine.search(fold(text)))for(const name of names){
      const start=end-name.length+1;
      if(/[a-z0-9]/.test(name[0])&&/[a-z0-9_]/i.test(text[start-1]||''))continue;
      if(/[a-z0-9]/.test(name.at(-1))&&/[a-z0-9_]/i.test(text[end+1]||''))continue;
      matches.push({start,length:name.length,text:text.slice(start,end+1),ids:aliases.get(name)});
    }
    matches.sort((a,b)=>a.start-b.start||b.length-a.length);
    const result=[];let end=0;
    for(const match of matches)if(match.start>=end){result.push(match);end=match.start+match.length;}
    return result;
  }};
}
export const buildJSON=input=>{const value=JSON.parse(input);return JSON.stringify(build(value.sources,value.documents));};
