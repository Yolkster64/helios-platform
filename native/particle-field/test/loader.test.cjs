'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { loadParticleField, LIMITS } = require('../index.cjs');

test('native plugin is disabled by default and requires explicit boolean opt-in', () => {
  assert.equal(loadParticleField(), null);
  assert.equal(loadParticleField({}), null);
  assert.equal(loadParticleField({ enabled: false }), null);
  for (const enabled of ['true', 1, null, {}]) {
    assert.throws(() => loadParticleField({ enabled }), TypeError);
  }
});

test('published limits are immutable', () => {
  assert.ok(Object.isFrozen(LIMITS));
  assert.throws(() => { LIMITS.maxParticles = Infinity; }, TypeError);
});
