const test = require('node:test');
const assert = require('node:assert/strict');
const index = require('../../Sources/LearningCore/Resources/Reader/content-index.js');

test('course paths resolve relative and repository-root wiki links across sections', () => {
  const result = index.build([
    {kind:'note',path:'lessons/01-linear.md',source:'# 线性模型\n- 前置：[[../exercises/01-linear#答案|练习]]'},
    {kind:'exercise',path:'exercises/01-linear.md',source:'# 自检\n## 答案\n[[lessons/01-linear|课程]]'}
  ]);
  assert.equal(result.graph.edges.length, 2);
  assert.equal(result.graph.unresolved.length, 0);
  assert.equal(result.files.notes[0].path, 'lessons/01-linear.md');
});

test('ordinary numbered courses sort naturally and expose document titles', () => {
  const result = index.build([10,2,1].map(n=>({kind:'note',path:`lessons/${n}.md`,source:`# 第${n}课`} )));
  assert.deepEqual(result.files.notes.map(f=>f.path), ['lessons/1.md','lessons/2.md','lessons/10.md']);
  assert.equal(result.files.notes[0].label, '第1课');
});
