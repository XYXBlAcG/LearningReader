(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports){
    module.exports=api;
    if(require.main===module){
      let source='';
      process.stdin.setEncoding('utf8');
      process.stdin.on('data',value=>source+=value);
      process.stdin.on('end',()=>process.stdout.write(api.buildJSON(source)));
    }
  }else root.ReaderContentIndex=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  const compare=(a,b)=>a<b?-1:a>b?1:0;
  const id=(kind,path,anchor='')=>kind+':'+path+(anchor?'#'+anchor:'');

  function headingId(text){
    return text.replace(/!?\[([^\]]+)\]\([^)]*\)/g,'$1').replace(/[`*_~]/g,'').replace(/\$+/g,'').trim().toLowerCase().replace(/\s+/g,'-').replace(/[^a-z0-9\u4e00-\u9fff-]/g,'')||'section';
  }

  function title(path,source){
    const match=source.match(/^#\s+(.+?)\s*$/m);
    return match?match[1].replace(/[`*_~]/g,'').trim():path.split('/').pop().replace(/\.[^.]+$/,'');
  }

  function normalize(path){
    const parts=[];
    for(const part of path.split('/')){
      if(!part||part==='.')continue;
      if(part==='..'){if(!parts.length)return null;parts.pop();}else parts.push(part);
    }
    return parts.join('/');
  }

  function plain(source){
    return source.replace(/(?<!!)\[\[([^\]\n]+)\]\]/g,(_,body)=>{
      const divider=body.indexOf('|'),hash=body.indexOf('#');
      return (divider>=0?body.slice(divider+1):'')||(hash>=0?body.slice(hash+1):'')||(divider>=0?body.slice(0,divider):body);
    }).replace(/!?\[([^\]]*)\]\([^)]*\)/g,'$1').replace(/<[^>]+>/g,' ').replace(/[`*_~]/g,'').replace(/\$+/g,' ').replace(/\\[\[\]()]/g,' ').replace(/\s+/g,' ').trim();
  }

  function sections(document){
    const {kind,path,source,label}=document;
    const result=[],used=new Set();
    let heading=label,anchor='',level=1,body=[],seen=false,fence=false;
    const append=()=>{
      const text=plain(body.join('\n'));
      if(heading||text)result.push({id:kind+':'+path+'#'+anchor,kind,path,documentLabel:label,heading:plain(heading),anchor,level,text});
    };
    for(const line of source.split(/\r?\n/)){
      if(/^\s*(```|~~~)/.test(line)){fence=!fence;continue;}
      if(fence)continue;
      const match=line.match(/^(#{1,6})\s+(.+?)\s*$/);
      if(!match){body.push(line);continue;}
      const current=match[2].trim(),depth=match[1].length;
      if(depth===1&&!seen){heading=current;level=depth;seen=true;used.add(headingId(current));continue;}
      append();heading=current;level=depth;body=[];
      const base=headingId(current);anchor=base;let number=2;
      while(used.has(anchor))anchor=base+'-'+number++;
      used.add(anchor);
    }
    append();
    return result;
  }

  function natural(value){
    return value.toLowerCase().split(/(\d+)/).filter(Boolean).map(part=>/^\d+$/.test(part)?[0,Number(part)]:[1,part]);
  }

  function compareNatural(a,b){
    const left=natural(a),right=natural(b);
    for(let n=0;n<Math.min(left.length,right.length);n++){
      const order=compare(left[n][0],right[n][0])||compare(left[n][1],right[n][1]);
      if(order)return order;
    }
    return compare(left.length,right.length);
  }

  function fileOrder(a,b){
    return compareNatural(a.path,b.path);
  }

  function build(input){
    const documents=input.map(value=>({...value,label:title(value.path,value.source),headings:{}})).sort((a,b)=>compare(a.kind==='note'?0:1,b.kind==='note'?0:1)||compare(a.path,b.path));
    const byId=new Map(),byPath=new Map(),nodes=[],nodeIds=new Set(),edges=[],edgeIds=new Set(),unresolved=[],backlinks={};
    for(const doc of documents){
      for(const match of doc.source.matchAll(/^#{1,6}\s+(.+?)\s*$/gm))doc.headings[headingId(match[1])]=match[1].trim();
      byId.set(id(doc.kind,doc.path),doc);byPath.set(doc.path,doc);
      const node={id:id(doc.kind,doc.path),kind:doc.kind,path:doc.path,anchor:'',label:doc.label,documentLabel:doc.label};
      nodes.push(node);nodeIds.add(node.id);
    }
    for(const doc of documents){
      const sourceId=id(doc.kind,doc.path);let fence=false;
      for(const line of doc.source.split(/\r?\n/)){
        if(/^\s*(```|~~~)/.test(line)){fence=!fence;continue;}
        if(fence)continue;
        const text=line.replace(/`[^`]*`/g,'');
        for(const match of text.matchAll(/(?<!!)\[\[([^\]\n]+)\]\]/g)){
          const body=match[1].trim(),divider=body.indexOf('|');
          const raw=(divider>=0?body.slice(0,divider):body).trim();
          const label=(divider>=0?body.slice(divider+1):raw.slice(raw.lastIndexOf('#')+1)).trim();
          const hash=raw.indexOf('#'),target=(hash>=0?raw.slice(0,hash):raw).trim();
          const anchor=hash>=0&&raw.slice(hash+1).trim()?headingId(raw.slice(hash+1)):'';
          const withExtension=/\.md$/i.test(target)?target:target+'.md';
          const destination=!target?doc.path:(byPath.has(withExtension)?withExtension:normalize(doc.path.split('/').slice(0,-1).concat(withExtension).join('/')));
          const targetDoc=byPath.get(destination);
          const kind=targetDoc?.kind,path=destination;
          if(!targetDoc||(anchor&&!Object.prototype.hasOwnProperty.call(targetDoc.headings,anchor))){unresolved.push({source:sourceId,target:raw,label});continue;}
          const targetId=id(kind,path,anchor);
          if(!nodeIds.has(targetId)){
            nodes.push({id:targetId,kind,path,anchor,label:label||targetDoc.headings[anchor],documentLabel:targetDoc.label});nodeIds.add(targetId);
          }
          const type=/(?:^|[-*]\s*)前置\s*[：:]/.test(line)?'prerequisite':/(?:^|[-*]\s*)延伸\s*[：:]/.test(line)?'extension':'related';
          const key=JSON.stringify([sourceId,targetId,type]);
          if(edgeIds.has(key))continue;
          edgeIds.add(key);edges.push({source:sourceId,target:targetId,type});
          (backlinks[targetId]??=[]).push(sourceId);
        }
      }
    }
    nodes.sort((a,b)=>compare(a.id,b.id));
    edges.sort((a,b)=>compare(a.source,b.source)||compare(a.target,b.target)||compare(a.type,b.type));
    unresolved.sort((a,b)=>compare(a.source,b.source)||compare(a.target,b.target));
    const orderedBacklinks={};
    Object.keys(backlinks).sort(compare).forEach(key=>orderedBacklinks[key]=[...new Set(backlinks[key])].sort(compare));
    const files={};
    for(const [kind,name] of [['note','notes'],['exercise','exercises']]){
      files[name]=documents.filter(doc=>doc.kind===kind).map(doc=>({path:doc.path,label:doc.label})).sort(fileOrder);
    }
    return {files,graph:{nodes,edges,backlinks:orderedBacklinks,unresolved},search:{version:1,sections:documents.flatMap(sections)}};
  }

  return {build,buildJSON:source=>JSON.stringify(build(JSON.parse(source)))};
});
