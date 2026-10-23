const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const scenes = require('../../Sources/LearningCore/Resources/Reader/geometry/problem-scenes.js');
const traces = require('../../Sources/LearningCore/Resources/Reader/geometry/traces.js');

test('construction steps cover every scene without moving points off their equations', () => {
  for (const id of Object.keys(scenes.registry)) {
    const model = scenes.build(id);
    assert.ok(model.steps.length >= 2, id);
    const keys = model.steps.flatMap(step => step.keys);
    assert.deepEqual([...keys].sort(), model.layers.map(layer => layer.key).sort());
    for (const progress of [0, .3, 1, model.steps.length - .5, model.steps.length]) {
      const visible = scenes.atProgress(model, progress);
      for (const layer of visible) for (const geometry of layer.geometry) {
        for (const point of geometry.type === 'surface' ? geometry.points.flat() : geometry.points) {
          if (geometry.residual) assert.ok(Math.abs(geometry.residual(point)) < 1e-7, id);
        }
      }
    }
    assert.deepEqual(scenes.atProgress(model, model.steps.length), model.layers);
    assert.deepEqual(scenes.atProgress(model, 0), []);
  }
});

test('every registered scene produces finite, equation-checked geometry', () => {
  for (const id of Object.keys(scenes.registry)) {
    for (const radius of [3, 6]) {
      const scene = scenes.build(id, {}, radius);
      assert.ok(scene.layers.length, id);
      for (const layer of scene.layers) {
        assert.ok(layer.name, id);
        for (const geometry of layer.geometry) {
          const points = geometry.type === 'surface' ? geometry.points.flat() : geometry.points;
          const trace = geometry.type === 'surface' ? traces.surface(geometry.points,layer.name,'#123456') : traces.line(geometry.points,layer.name,'#123456');
          assert.equal(trace.name,layer.name);
          assert.deepEqual(trace.x.flat(),points.map(point=>point[0]));
          assert.deepEqual(trace.y.flat(),points.map(point=>point[1]));
          assert.deepEqual(trace.z.flat(),points.map(point=>point[2]));
          for (const point of points) {
            assert.ok(point.every(Number.isFinite), id + ':' + layer.name);
            if (geometry.residual) assert.ok(Math.abs(geometry.residual(point)) < 1e-7, id + ':' + layer.name);
          }
        }
      }
    }
  }
});

test('degenerate slices and circle parameters remain honest', () => {
  const empty = scenes.build('ellipsoid-sections', {h: 3}, 4);
  assert.equal(empty.layers.find(layer => layer.key === 'section').geometry.length, 0);
  const point = scenes.build('cone-circle', {a: 0}, 4);
  assert.deepEqual(point.layers.find(layer => layer.key === 'section').geometry[0].points, [[0, 0, 0]]);
  assert.match(scenes.build('homework-10', {}, 4).description, /不属于/);
});

test('every parameter endpoint preserves the sampled equations', () => {
  for (const id of Object.keys(scenes.registry)) {
    const initial = scenes.build(id);
    for (const option of initial.controls) {
      for (const value of [option.min, option.max]) {
        const model = scenes.build(id, {[option.key]:value}, 6);
        for (const layer of model.layers) for (const geometry of layer.geometry) {
          const points = geometry.type === 'surface' ? geometry.points.flat() : geometry.points;
          for (const point of points) {
            assert.ok(point.every(Number.isFinite), id);
            if (geometry.residual) assert.ok(Math.abs(geometry.residual(point)) < 1e-7, id);
          }
        }
      }
    }
  }
});

test('projections satisfy both original constraints and their range restrictions', () => {
  for (const id of ['restricted-projection','homework-29']) {
    const model = scenes.build(id);
    const factor = id === 'homework-29' ? 2 : 1;
    for (const geometry of model.layers.find(layer => layer.key === 'source').geometry) {
      for (const [x,y,z] of geometry.points) assert.ok(Math.abs(z*z-factor*x*y)<1e-8);
    }
    for (const geometry of model.layers.find(layer => layer.key === 'projection').geometry) {
      for (const [x,y,z] of geometry.points) {
        assert.equal(z,0);
        assert.ok(x*y>=-1e-10);
        if(id==='homework-29') assert.ok(Math.abs(Math.abs(x+y)-2)<1e-8);
      }
    }
  }
});

test('homework 10 distinguishes actual generated points from excluded directions', () => {
  const model=scenes.build('homework-10');
  for(const geometry of model.layers.find(layer=>layer.key==='surface').geometry) {
    for(const [x,y,z] of geometry.points.flat()) {
      const atVertex=Math.hypot(x-3,y-2,z-1)<1e-9;
      assert.ok(atVertex || Math.abs(x-y+z-2)>1e-9);
    }
  }
  for(const geometry of model.layers.find(layer=>layer.key==='directrix').geometry) {
    for(const [x,y,z] of geometry.points) assert.ok(Math.abs(x-y+z)<1e-9);
  }
});
