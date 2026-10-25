import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const require = createRequire(import.meta.url);
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(root,'Sources/LearningCore/Resources/Reader/vendor');
const entry = require.resolve('marked-cjk-friendly');
const options = {bundle:true,format:'iife',target:'es2020',minify:true,write:false,legalComments:'inline'};
const result = await build({...options,entryPoints:[entry],globalName:'ReaderCJK'});
const marked = require.resolve('marked');
const parser = await build({...options,entryPoints:[marked],globalName:'marked'});
const files = new Map([
  ['marked-cjk-friendly.min.js',result.outputFiles[0].text],
  ['marked-cjk-friendly-LICENSE',readFileSync(resolve(dirname(entry),'../LICENSE'),'utf8')],
  ['marked.min.js',parser.outputFiles[0].text],
  ['marked-LICENSE',readFileSync(resolve(dirname(marked),'../LICENSE'),'utf8')]
]);
for (const [name,text] of files) {
  const path = resolve(output,name);
  if (process.argv.includes('--check')) {
    if (readFileSync(path,'utf8') !== text) throw new Error('Regenerate reader dependency: ' + name);
  } else { writeFileSync(path,text); }
}
