const test=require('node:test');
const assert=require('node:assert/strict');
const {GeometryViewState}=require('../../Sources/LearningCore/Resources/Reader/geometry/view-state.js');
const G=require('../../Sources/LearningCore/Resources/Reader/geometry/models.js');

test('playback accumulates small frames without relying on rounded slider values',()=>{
  const {GeometryPlayback}=require('../../Sources/LearningCore/Resources/Reader/geometry/view-state.js');
  const playback=new GeometryPlayback(3);
  assert.equal(playback.progress,3);
  playback.play();playback.tick(0);
  for(let time=16;time<=960;time+=16)playback.tick(time);
  assert.ok(playback.progress>.39&&playback.progress<.41);
  playback.pause();const paused=playback.progress;playback.tick(2000);
  assert.equal(playback.progress,paused);
  playback.seek(1);playback.play();playback.tick(3000);playback.tick(3100);
  assert.ok(playback.progress>1);
  playback.seek(2.99);playback.play();playback.tick(4000);playback.tick(4100);
  assert.equal(playback.progress,3);assert.equal(playback.playing,false);
});

test('changing drawing extent leaves camera and zoom unchanged',()=>{
  const state=new GeometryViewState();
  state.zoom(.5);
  state.setCamera({eye:{x:2,y:-1,z:.4},up:{x:0,y:0,z:1},projection:{type:'orthographic'}});
  const previous=structuredClone(state.camera);
  state.setRenderRadius(15);
  assert.equal(state.displayRadius,1.5);
  assert.equal(state.renderRadius,15);
  assert.deepEqual(state.camera,previous);
  state.fitDrawing();
  assert.equal(state.displayRadius,15);
  assert.deepEqual(state.camera,previous);
});

test('camera updates are copied and reset is deliberate',()=>{
  const state=new GeometryViewState();
  const camera={eye:{x:0,y:0,z:4}};
  state.setCamera(camera);
  camera.eye.z=9;
  assert.equal(state.camera.eye.z,4);
  state.resetView();
  assert.equal(state.displayRadius,3);
  assert.equal(state.camera.eye.x,1.7);
});

test('larger extents generate larger actual meshes without changing their equations',()=>{
  for(const key of ['single','double','cylinder','cone','paraboloid','saddle']){
    const model=G.quadrics[key];
    const small=G.surfacePatches(model,3).flat(2);
    const big=G.surfacePatches(model,12).flat(2);
    const extent=points=>Math.max(...points.flat().map(Math.abs));
    assert.ok(extent(big)>extent(small),key);
    for(const point of big) assert.ok(Math.abs(G.residual(model,point))<1e-8,key);
  }
  const small=G.section(G.quadrics.cone,0,0,3).curves.flat();
  const big=G.section(G.quadrics.cone,0,0,12).curves.flat();
  assert.ok(Math.max(...big.flat().map(Math.abs))>Math.max(...small.flat().map(Math.abs)));
});
