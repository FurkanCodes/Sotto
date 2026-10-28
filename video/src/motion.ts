import {Easing, interpolate, spring} from 'remotion';
import {FPS} from './theme';

export const EASE = Easing.bezier(0.16, 1, 0.3, 1);

/** 0 → 1 after `start`, springing in over about half a second. */
export const pop = (frame: number, start: number, damping = 18, mass = 0.6) =>
  spring({frame: frame - start, fps: FPS, config: {damping, mass, stiffness: 140}});

/** 0 → 1 between two frames with the spring-like ease. */
export const ramp = (frame: number, from: number, to: number) =>
  interpolate(frame, [from, to], [0, 1], {easing: EASE, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

/** A scene's fade in at the start and out at the end. */
export const sceneFade = (frame: number, frames: number, edge = 12) =>
  Math.min(ramp(frame, 0, edge), 1 - ramp(frame, frames - edge, frames));

export const mix = (a: number, b: number, t: number) => a + (b - a) * t;
