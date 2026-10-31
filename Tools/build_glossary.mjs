import {build} from 'esbuild';
import Ajv from 'ajv';
import standalone from 'ajv/dist/standalone/index.js';
import {readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname,resolve} from 'node:path';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const schema=JSON.parse(readFileSync(resolve(root,'Schemas/glossary.schema.json'),'utf8'));
const ajv=new Ajv({code:{source:true,esm:true},strict:true});
const validation=standalone(ajv,ajv.compile(schema));
const result=await build({entryPoints:[resolve(root,'Tools/reader/glossary-core.js')],bundle:true,format:'iife',globalName:'ReaderGlossaryCore',target:'es2020',minify:true,write:false,plugins:[{
  name:'glossary-schema',setup(builder){
    builder.onResolve({filter:/^glossary-schema$/},()=>({path:'schema',namespace:'glossary'}));
    builder.onLoad({filter:/.*/,namespace:'glossary'},()=>({contents:validation,loader:'js',resolveDir:root}));
  }
}]});
const source=result.outputFiles[0].text+'\nif(typeof module==="object"&&module.exports)module.exports=ReaderGlossaryCore;\n';
const output=resolve(root,'Sources/LearningCore/Resources/Reader/glossary-core.js');
if(process.argv.includes('--check')){
  if(readFileSync(output,'utf8')!==source)throw new Error('术语依赖需重新生成：node Tools/build_glossary.mjs');
}else writeFileSync(output,source);
const ui=await build({entryPoints:[resolve(root,'Tools/reader/glossary-ui.js')],bundle:true,format:'iife',globalName:'ReaderGlossaryUI',target:'es2020',minify:true,write:false,legalComments:'inline'});
const uiPath=resolve(root,'Sources/LearningCore/Resources/Reader/glossary-ui.js');
if(process.argv.includes('--check')){
  if(readFileSync(uiPath,'utf8')!==ui.outputFiles[0].text)throw new Error('术语视图需重新生成');
}else writeFileSync(uiPath,ui.outputFiles[0].text);
for(const [name,path] of [['mark.js','mark.js/LICENSE'],['ahocorasick','ahocorasick/LICENSE'],['floating-ui','@floating-ui/dom/LICENSE']]){
  const source=readFileSync(resolve(root,'node_modules',path),'utf8');
  const target=resolve(root,'Sources/LearningCore/Resources/Reader/vendor',name+'-LICENSE');
  if(process.argv.includes('--check')){if(readFileSync(target,'utf8')!==source)throw new Error('License differs: '+name);}
  else writeFileSync(target,source);
}
