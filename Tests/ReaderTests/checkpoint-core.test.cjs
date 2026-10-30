const test=require('node:test');
const assert=require('node:assert/strict');
const fixture=require('../Fixtures/checkpoint.json');
const core=require('../../Sources/LearningCore/Resources/Reader/checkpoint-core.js');
const block=q=>'```checkpoint\n'+JSON.stringify(q)+'\n```\n';

test('structured extraction preserves LaTeX, ignores other fences, rejects nested and malformed blocks',()=>{
 const source='# 课程\n## 定义\n\n'+block(fixture)+'\n~~~js\nconst text = "```checkpoint";\n~~~';
 const found=core.extract(source);
 assert.equal(found.length,1);assert.equal(found[0].question.stem,fixture.stem);
 assert.equal(source.slice(found[0].start,found[0].end).trim(),block(fixture).trim());
 assert.throws(()=>core.extract('```checkpoint\n{bad}\n```'),/JSON/);
 assert.throws(()=>core.extract(block({...fixture,correct:['missing']})),/选项/);
 assert.throws(()=>core.extract('> '+block(fixture).trim().split('\n').join('\n> ')),/顶层/);
 assert.throws(()=>core.extract(block({...fixture,typo:true})),/字段|property|properties/);
});

test('single and exact-set multiple grading distinguish empty, missing and extra selections',()=>{
 assert.throws(()=>core.grade(fixture,[]),/选择/);
 assert.throws(()=>core.grade(fixture,['fake']),/选项/);
 assert.equal(core.grade(fixture,['one']).correct,true);
 assert.deepEqual(core.grade(fixture,['two']),{correct:false,missing:['one'],extra:['two']});
 const q={...fixture,type:'multiple',correct:['one','two']};
 assert.equal(core.grade(q,['two','one']).correct,true);
 assert.deepEqual(core.grade(q,['one']).missing,['two']);
 assert.throws(()=>core.grade(fixture,['one','one']),/重复/);
});

test('content signature survives feedback edits and option reordering but changes with answers',()=>{
 assert.equal(core.signature(fixture),core.signature({...fixture,explanation:'新讲解',options:[...fixture.options].reverse()}));
 assert.notEqual(core.signature(fixture),core.signature({...fixture,correct:['two']}));
});

test('course catalog validates identity and review anchors while projection excludes answer metadata',()=>{
 const doc={kind:'note',path:'lesson.md',source:'# 课程\n## 定义\n'+block(fixture)};
 assert.equal(core.catalog([doc])[0].question.id,fixture.id);
 assert.throws(()=>core.catalog([doc,{...doc,path:'copy.md'}]),/重复/);
 assert.throws(()=>core.catalog([{...doc,source:doc.source.replace('## 定义','## 另一定义')}]),/回看/);
 const projected=core.project(doc.source);
 assert.ok(projected.includes(fixture.stem));assert.ok(!projected.includes('correct'));assert.ok(!projected.includes(fixture.explanation));
});
