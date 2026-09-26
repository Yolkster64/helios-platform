'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { loadParticleField, LIMITS } = require('../index.cjs');
// A missing/unloadable binary fails this suite; it is never recorded as a skip.
const { update } = loadParticleField({ enabled: true });

function bytes(array) {
  return Buffer.from(new Uint8Array(array.buffer, array.byteOffset, array.byteLength));
}

function rejectsWithoutMutation(positions, velocities, delta, error = RangeError) {
  const beforePositions = bytes(positions);
  const beforeVelocities = bytes(velocities);
  assert.throws(() => update(positions, velocities, delta), error);
  assert.deepEqual(bytes(positions), beforePositions);
  assert.deepEqual(bytes(velocities), beforeVelocities);
}

test('batch update applies attraction and damping to actual xyz positions', () => {
  const positions = new Float32Array([10, -20, 30, -4, 5, -6]);
  const velocities = new Float32Array([1, 2, 3, -1, -2, -3]);
  const beforePositions = positions.slice();
  const beforeVelocities = velocities.slice();
  const delta = 0.025;
  assert.equal(update(positions, velocities, delta), undefined);
  for (let i = 0; i < positions.length; ++i) {
    const nextVelocity = (beforeVelocities[i] - LIMITS.attraction * beforePositions[i] * delta)
      * Math.exp(-LIMITS.damping * delta);
    assert.equal(velocities[i], Math.fround(nextVelocity));
    assert.equal(positions[i], Math.fround(beforePositions[i] + nextVelocity * delta));
  }
  assert.notDeepEqual(positions, beforePositions);
  assert.notDeepEqual(velocities, beforeVelocities);
});

test('stationary off-origin particles move toward the origin', () => {
  const positions = new Float32Array([30, -40, 50]);
  const velocities = new Float32Array(3);
  for (let frame = 0; frame < 120; ++frame) update(positions, velocities, 1 / 60);
  assert.ok(positions[0] > 0 && positions[0] < 30);
  assert.ok(positions[1] < 0 && positions[1] > -40);
  assert.ok(positions[2] > 0 && positions[2] < 50);
});

test('zero step preserves valid values including signed zero', () => {
  const positions = new Float32Array([-0, 10, -20]);
  const velocities = new Float32Array([0, -0, 1]);
  const before = [bytes(positions), bytes(velocities)];
  update(positions, velocities, 0);
  assert.deepEqual([bytes(positions), bytes(velocities)], before);
});

test('allows maximum batch and timestep', () => {
  const positions = new Float32Array(LIMITS.maxParticles * 3).fill(10);
  const velocities = new Float32Array(positions.length);
  update(positions, velocities, LIMITS.maxDeltaSeconds);
  assert.ok(positions[0] < 10);
  assert.equal(positions[0], positions.at(-1));
  assert.ok(velocities.at(-1) < 0);
});

test('disjoint views sharing one ArrayBuffer are accepted and respect offsets', () => {
  const storage = new Float32Array([999, 999, 999, 10, 20, 30, 1, 2, 3, 888, 888, 888]);
  update(storage.subarray(3, 6), storage.subarray(6, 9), 0.01);
  assert.deepEqual([...storage.subarray(0, 3)], [999, 999, 999]);
  assert.deepEqual([...storage.subarray(9)], [888, 888, 888]);
  assert.notEqual(storage[3], 10);
  assert.notEqual(storage[6], 1);
});

test('overlapping views in either order are rejected without mutation', () => {
  const storage = new Float32Array(9).fill(3);
  rejectsWithoutMutation(storage.subarray(0, 6), storage.subarray(3, 9), 0.01);
  rejectsWithoutMutation(storage.subarray(3, 9), storage.subarray(0, 6), 0.01);
  rejectsWithoutMutation(storage, storage, 0.01);
});

test('requires two Float32Arrays and exactly three arguments', () => {
  const valid = new Float32Array(3);
  for (const invalid of [null, undefined, {}, [], new Float64Array(3), new Uint32Array(3), Buffer.alloc(12)]) {
    assert.throws(() => update(invalid, valid, 0.01), TypeError);
    assert.throws(() => update(valid, invalid, 0.01), TypeError);
  }
  assert.throws(() => update(), TypeError);
  assert.throws(() => update(valid, new Float32Array(3)), TypeError);
  assert.throws(() => update(valid, new Float32Array(3), 0.01, 'extra'), TypeError);
  assert.deepEqual([...valid], [0, 0, 0]);
});

test('rejects empty, non-xyz, unequal and oversized batches', () => {
  for (const [a, b] of [[0, 0], [2, 2], [3, 6], [LIMITS.maxParticles * 3 + 3, LIMITS.maxParticles * 3 + 3]]) {
    rejectsWithoutMutation(new Float32Array(a), new Float32Array(b), 0.01);
  }
});

test('requires a finite timestep within the fixed bound, without coercion', () => {
  for (const delta of [-1, -Number.MIN_VALUE, NaN, Infinity, -Infinity, 0.05000001]) {
    rejectsWithoutMutation(new Float32Array([1, 2, 3]), new Float32Array([4, 5, 6]), delta);
  }
  for (const delta of ['0.01', 0n, {}, null, undefined, new Number(0.01)]) {
    rejectsWithoutMutation(new Float32Array([1, 2, 3]), new Float32Array([4, 5, 6]), delta, TypeError);
  }
});

test('late invalid input never leaves an earlier particle partially updated', () => {
  for (const invalid of [NaN, Infinity, -Infinity, 1_000_001, -1_000_001]) {
    for (const target of ['positions', 'velocities']) {
      const positions = new Float32Array([1, 2, 3, 4, 5, 6]);
      const velocities = new Float32Array([6, 5, 4, 3, 2, 1]);
      (target === 'positions' ? positions : velocities)[5] = invalid;
      rejectsWithoutMutation(positions, velocities, 0.01);
    }
  }
});

test('rejects a proposed out-of-bounds output before any mutation', () => {
  const positions = new Float32Array([1, 2, 3, 0, 0, LIMITS.maxComponent]);
  const velocities = new Float32Array([6, 5, 4, 0, 0, LIMITS.maxComponent]);
  rejectsWithoutMutation(positions, velocities, LIMITS.maxDeltaSeconds);
});

test('zero step still validates all inputs', () => {
  rejectsWithoutMutation(new Float32Array([0, NaN, 0]), new Float32Array(3), 0);
});

test('shared memory is rejected to prevent concurrent mutation', () => {
  const shared = new Float32Array(new SharedArrayBuffer(12));
  shared.set([1, 2, 3]);
  rejectsWithoutMutation(shared, new Float32Array(3), 0.01, TypeError);
  rejectsWithoutMutation(new Float32Array(3), shared, 0.01, TypeError);
});

test('detached memory is rejected without touching the other array', () => {
  const detached = new Float32Array([1, 2, 3]);
  structuredClone(detached.buffer, { transfer: [detached.buffer] });
  const other = new Float32Array([3, 2, 1]);
  assert.throws(() => update(detached, other, 0.01), RangeError);
  assert.throws(() => update(other, detached, 0.01), RangeError);
  assert.deepEqual([...other], [3, 2, 1]);
});
