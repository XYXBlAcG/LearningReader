const test = require('node:test');
const assert = require('node:assert/strict');
const {storage,resolve} = require('../../Sources/LearningCore/Resources/Reader/course-context.js');
function memory(){const data=new Map();return {get length(){return data.size},key:i=>[...data.keys()][i],getItem:k=>data.has(k)?data.get(k):null,setItem:(k,v)=>data.set(k,String(v)),removeItem:k=>data.delete(k)}}
test('course reading states are isolated while font preference is global',()=>{
 const raw=memory(),a=storage(raw,'a'),b=storage(raw,'b');
 a.setItem('reader_last','A');b.setItem('reader_last','B');
 assert.equal(a.getItem('reader_last'),'A');assert.equal(b.getItem('reader_last'),'B');
 a.setItem('reader_zoom','1.2');assert.equal(b.getItem('reader_zoom'),'1.2');
});
test('legacy migration prefixes document paths once without resurrecting cleared history',()=>{
 const raw=memory();raw.setItem('reader_last',JSON.stringify({kind:'note',path:'微积分/A.md'}));
 const a=storage(raw,'math',true);assert.equal(JSON.parse(a.getItem('reader_last')).path,'数学笔记/微积分/A.md');
 a.removeItem('reader_last');assert.equal(storage(raw,'math',true).getItem('reader_last'),null);
});
test('relative and root links resolve against actual indexed documents',()=>{
 const files={notes:[{path:'lessons/a.md'}],exercises:[{path:'tasks/a.md'}]};
 assert.deepEqual(resolve('../tasks/a.md',{kind:'note',path:'lessons/a.md'},files),{kind:'exercise',path:'tasks/a.md'});
 assert.equal(resolve('../../../outside.md',{kind:'note',path:'lessons/a.md'},files),null);
});

test('desktop state seed is imported only into its course once',()=>{
 const raw=memory();const seed={reader_last:JSON.stringify({kind:'exercise',path:'A.md'}),other:'ignored'};
 const view=storage(raw,'math',true,seed);
 assert.equal(JSON.parse(view.getItem('reader_last')).path,'数学练习/A.md');
 assert.equal(raw.getItem('other'),null);
 view.removeItem('reader_last');assert.equal(storage(raw,'math',true,seed).getItem('reader_last'),null);
});
