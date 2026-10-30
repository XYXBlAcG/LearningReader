import {build} from 'esbuild';
import Ajv from 'ajv';
import standalone from 'ajv/dist/standalone/index.js';
import {readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname,resolve} from 'node:path';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const schema=JSON.parse(readFileSync(resolve(root,'Schemas/checkpoint.schema.json'),'utf8'));
const ajv=new Ajv({code:{source:true,esm:true},strict:true});
const validation=standalone(ajv,ajv.compile(schema));
const result=await build({entryPoints:[resolve(root,'Tools/reader/checkpoint-core.js')],bundle:true,format:'iife',globalName:'ReaderCheckpoints',target:'es2020',minify:true,write:false,plugins:[{
  name:'checkpoint-schema',setup(builder){
    builder.onResolve({filter:/^checkpoint-schema$/},()=>({path:'schema',namespace:'checkpoint'}));
    builder.onLoad({filter:/.*/,namespace:'checkpoint'},()=>({contents:validation,loader:'js',resolveDir:root}));
  }
}]});
const source=result.outputFiles[0].text+'\nif(typeof module==="object"&&module.exports)module.exports=ReaderCheckpoints;\n';
const output=resolve(root,'Sources/LearningCore/Resources/Reader/checkpoint-core.js');
if(process.argv.includes('--check')){
  if(readFileSync(output,'utf8')!==source)throw new Error('自测依赖需重新生成：node Tools/build_checkpoints.mjs');
}else writeFileSync(output,source);
const license=readFileSync(resolve(root,'node_modules/ajv/LICENSE'),'utf8').trimEnd()+'\n';
const licensePath=resolve(root,'Sources/LearningCore/Resources/Reader/vendor/ajv-LICENSE');
if(process.argv.includes('--check')){
  if(readFileSync(licensePath,'utf8')!==license)throw new Error('Ajv license requires regeneration');
}else writeFileSync(licensePath,license);
