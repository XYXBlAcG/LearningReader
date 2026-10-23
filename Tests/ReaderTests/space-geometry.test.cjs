const test = require('node:test');
const assert = require('node:assert/strict');
const geometry = require('../../Sources/LearningCore/Resources/Reader/geometry/models.js');

const near = (a, b, tolerance = 1e-8) => assert.ok(Math.abs(a - b) < tolerance, `${a} != ${b}`);

test('surface samples satisfy the unique quadratic model', () => {
  for (const model of Object.values(geometry.quadrics)) {
    for (const patch of geometry.surfacePatches(model)) {
      for (const row of patch) for (const point of row) near(geometry.residual(model, point), 0);
    }
  }
});

test('all three slice directions produce points on the surface and cutting plane', () => {
  for (const model of Object.values(geometry.quadrics)) {
    for (const axis of [0, 1, 2]) for (const height of [-2, -1, 0, 0.5, 1, 2]) {
      const section = geometry.section(model, axis, height);
      for (const branch of section.curves) for (const point of branch) {
        near(point[axis], height);
        near(geometry.residual(model, point), 0, 1e-7);
        assert.ok(point.every(Number.isFinite));
      }
    }
  }
});

test('empty, point and degenerate sections are distinguished', () => {
  const q = geometry.quadrics;
  assert.equal(geometry.section(q.ellipsoid, 2, 3).kind, '空集');
  assert.equal(geometry.section(q.ellipsoid, 2, 2).kind, '一个点');
  assert.equal(geometry.section(q.double, 2, 0).kind, '空集');
  assert.equal(geometry.section(q.double, 2, 1).kind, '一个点');
  assert.equal(geometry.section(q.saddle, 2, 0).kind, '两条相交直线');
  assert.equal(geometry.section(q.cylinder, 1, 1).kind, '一条直线');
  assert.equal(geometry.section(q.cylinder, 1, 0).kind, '两条平行直线');
  assert.equal(geometry.section(q.paraboloid, 0, 0).kind, '抛物线');
});

test('the closest connector is perpendicular to both original lines', () => {
  const result = geometry.connector(1 / 3, -1 / 3);
  near(result.dot1, 0);
  near(result.dot2, 0);
  near(result.distance, 2 / Math.sqrt(3));
  assert.ok(geometry.connector(1, 1).distance > result.distance);
});

test('projection removes the normal component including the point degeneration', () => {
  const plane = {normal: [1, 1, 1], constant: 0};
  near(geometry.dot(geometry.project([2, 0, 1], plane), plane.normal), 0);
  assert.deepEqual(geometry.projectDirection([1, 1, 1], plane), [0, 0, 0]);
});
