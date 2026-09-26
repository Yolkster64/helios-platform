'use strict';

const LIMITS = Object.freeze({
  maxParticles: 100_000,
  maxDeltaSeconds: 0.05,
  maxComponent: 1_000_000,
  attraction: 0.35,
  damping: 0.8,
});

/** Explicit opt-in only. This package never loads native code on import. */
function loadParticleField({ enabled = false } = {}) {
  if (typeof enabled !== 'boolean') {
    throw new TypeError('enabled must be a boolean');
  }
  if (!enabled) return null;

  // Fixed bundled path only: no user-controlled binary search or fallback.
  return require('./build/Release/particle_field.node');
}

module.exports = Object.freeze({ loadParticleField, LIMITS });
