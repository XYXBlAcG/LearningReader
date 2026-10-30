const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {JSDOM}=require('jsdom'),{IDBFactory}=require('fake-indexeddb');
const fixture=require('../Fixtures/checkpoint.json');
const base=path.resolve(__dirname,'../../Sources/LearningCore/Resources/Reader');

test('browser adapter persists drafts and attempts across reopen, isolates courses and rejects stale signatures',async()=>{
 const dom=new JSDOM('',{runScripts:'outside-only',url:'https://offline.test/'}),w=dom.window;
 w.indexedDB=new IDBFactory();
 for(const f of ['checkpoint-core.js','checkpoint-store.js'])w.eval(fs.readFileSync(path.join(base,f),'utf8'));
 const sig=w.ReaderCheckpoints.signature(fixture),Store=w.ReaderCheckpointStore.Store;
 const first=new Store('math',[fixture]);
 try{
  await first.request({action:'draft',questionID:fixture.id,signature:sig,selected:['two'],mode:'editing'});
  const command={action:'submit',questionID:fixture.id,signature:sig,selected:['two'],eventID:'first'};
  await first.request(command);await first.request(command);first.close();
  const reopened=new Store('math',[fixture]),state=await reopened.request({action:'load'});
  assert.equal(state.attempts.length,1);assert.equal(state.attempts[0].correct,false);assert.equal(state.drafts[0].mode,'feedback');
  await assert.rejects(reopened.request({...command,signature:'old'}),/版本/);
  const other=new Store('other',[fixture]);assert.equal((await other.request({action:'load'})).attempts.length,0);
  other.close();reopened.close();
 }finally{first.close();dom.window.close();}
});
