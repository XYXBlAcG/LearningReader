import {readdirSync,readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const {pdfTests}=JSON.parse(readFileSync('Config/Validation.json','utf8'));
const files=readdirSync('Tests/ReaderTests').filter(name=>name.endsWith('.test.cjs')&&(pdfTests||name!=='exercise-paper.test.cjs')).map(name=>'Tests/ReaderTests/'+name);
if(!pdfTests)process.stdout.write('PDF-specific tests skipped by release validation configuration\n');
const result=spawnSync(process.execPath,['--test',...files],{stdio:'inherit'});
if(result.error)throw result.error;
process.exit(result.status??1);
