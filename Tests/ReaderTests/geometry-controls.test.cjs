const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const reader=path.resolve(__dirname,'../../Sources/LearningCore/Resources/Reader');

test('embedded pages have a resize frame and fullscreen action',()=>{
  const app=fs.readFileSync(path.join(reader,'app.js'),'utf8');
  const css=fs.readFileSync(path.join(reader,'style.css'),'utf8');
  assert.match(app,/showModal/);
  assert.match(app,/interactive-viewport/);
  assert.match(css,/resize:\s*vertical/);
  assert.match(css,/:modal/);
});

test('geometry offers local zoom and resizes plots when their container changes',()=>{
  const app=fs.readFileSync(path.join(reader,'geometry/app.js'),'utf8');
  assert.match(app,/scrollZoom:\s*false/);
  assert.match(app,/addEventListener\('wheel'/);
  assert.match(app,/ResizeObserver/);
  assert.match(app,/Plots\.resize/);
  assert.match(app,/dataset\.zoom/);
  assert.match(app,/复位/);
});
