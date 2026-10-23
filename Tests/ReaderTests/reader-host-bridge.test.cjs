const test = require('node:test');
const assert = require('node:assert/strict');
const { createBridge } = require('../../Sources/LearningCore/Resources/Reader/host-bridge.js');

test('native bridge only hides web controls after connecting and publishes shared state', () => {
  const sent = [], calls = [];
  const bridge = createBridge({ read: () => ({ canBack: true }), dispatch: (name, payload) => calls.push([name, payload]) }, value => sent.push(value));
  assert.equal(bridge.connected, false);
  bridge.connect();
  assert.equal(bridge.connected, true);
  assert.equal(sent[0].state.canBack, true);
  bridge.dispatch('back');
  assert.deepEqual(calls, [['back', undefined]]);
});
