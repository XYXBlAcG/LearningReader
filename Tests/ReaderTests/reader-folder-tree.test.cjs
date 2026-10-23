const test=require('node:test');
const assert=require('node:assert/strict');
const {buildFolderTree,folderIsOpen,setExpansion}=require('../../Sources/LearningCore/Resources/Reader/sidebar-tree.js');
test('actual folders define nested chapters',()=>{
 const tree=buildFolderTree([{path:'微积分/02-02-极限/01-数列与函数极限/01-数列.md'},{path:'微积分/00-总览.md'},{path:'微积分/02-02-极限/01-数列与函数极限/方法课/01-夹逼.md'}]);
 assert.equal(tree[0].file.path,'微积分/00-总览.md');
 assert.equal(tree[1].label,'02-02-极限');
 assert.equal(tree[1].children[0].label,'01-数列与函数极限');
 assert.equal(tree[1].children[0].children[0].depth,2);
 assert.equal(tree[1].children[0].children[1].children[0].depth,3);
});
test('saved collapse overrides the active document default',()=>{
 assert.equal(folderIsOpen({},'note:a','a','a/01.md'),true);
 assert.equal(folderIsOpen({'note:a':true},'note:a','a','a/01.md'),false);
 assert.equal(folderIsOpen({'note:a':false},'note:a','a','b/01.md'),true);
});
test('bulk expansion stores every nested key and preserves other state',()=>{
 const state={unrelated:true};
 setExpansion(state,['note','note:main','note:a','note:a/b'],true);
 assert.equal(state['note:a/b'],false);
 assert.equal(state.unrelated,true);
 setExpansion(state,['note','note:main','note:a','note:a/b'],false);
 assert.equal(state['note:a/b'],true);
});
