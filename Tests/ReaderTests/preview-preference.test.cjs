const test=require('node:test');
const assert=require('node:assert/strict');
const {previewEnabled}=require('../../Sources/LearningCore/Resources/Reader/preview-preference.js');

test('narrow screens default to no 3D loading',()=>{
  assert.equal(previewEnabled(null,true),false);
  assert.equal(previewEnabled(null,false),true);
});

test('explicit choices override screen width',()=>{
  assert.equal(previewEnabled('true',true),true);
  assert.equal(previewEnabled('false',false),false);
});
