export interface ParticleField {
  /** Mutates both xyz arrays. Throws before any mutation if validation fails. */
  update(positions: Float32Array, velocities: Float32Array, deltaSeconds: number): void;
}

export declare const LIMITS: Readonly<{
  maxParticles: 100000;
  maxDeltaSeconds: 0.05;
  maxComponent: 1000000;
  attraction: 0.35;
  damping: 0.8;
}>;

/** Returns null unless explicitly enabled. Native loading failures propagate. */
export declare function loadParticleField(options?: { enabled?: boolean }): ParticleField | null;
