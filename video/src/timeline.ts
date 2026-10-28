import timing from '../public/narration/timing.json';
import {FPS, onInk, onPaper, type Tone} from './theme';

export type SceneId =
  | 'open' | 'hook' | 'dictate' | 'clean' | 'style' | 'send' | 'words'
  | 'keys' | 'models' | 'quiet' | 'battery' | 'private' | 'more' | 'end';

type Clip = {file: string; duration: number; words: {text: string; start: number; end: number}[]};
const clips = timing.clips as Record<string, Clip>;

// Midnight and fog alternate, so every cut is also a change of light. Each
// scene runs at least `frames`, and long enough for its line plus `tail` s.
const SPECS: {id: SceneId; frames: number; tone: Tone; voiceAt: number; tail: number}[] = [
  {id: 'open', frames: 150, tone: onInk, voiceAt: 1.0, tail: 0.6},
  {id: 'hook', frames: 140, tone: onPaper, voiceAt: 0.4, tail: 0.6},
  {id: 'dictate', frames: 330, tone: onPaper, voiceAt: 0.8, tail: 1.4},
  {id: 'clean', frames: 230, tone: onInk, voiceAt: 0.6, tail: 1.4},
  {id: 'style', frames: 230, tone: onPaper, voiceAt: 0.5, tail: 1.6},
  {id: 'send', frames: 230, tone: onInk, voiceAt: 2.4, tail: 1.6},
  {id: 'words', frames: 290, tone: onPaper, voiceAt: 0.5, tail: 2.0},
  {id: 'keys', frames: 250, tone: onInk, voiceAt: 0.5, tail: 1.2},
  {id: 'models', frames: 240, tone: onPaper, voiceAt: 0.4, tail: 1.6},
  {id: 'quiet', frames: 250, tone: onInk, voiceAt: 0.6, tail: 1.4},
  {id: 'battery', frames: 190, tone: onPaper, voiceAt: 0.4, tail: 1.4},
  {id: 'private', frames: 220, tone: onInk, voiceAt: 0.5, tail: 1.0},
  {id: 'more', frames: 260, tone: onPaper, voiceAt: 3.6, tail: 1.2},
  {id: 'end', frames: 210, tone: onInk, voiceAt: 1.2, tail: 2.4},
];

/** Frames each incoming scene wipes over the outgoing one. */
export const WIPE = 16;

/** A scene's narration line; frames are relative to the scene's start. */
export type Voice = {file: string; at: number; frames: number; words: {text: string; from: number; to: number}[]};
export type Scene = {id: SceneId; from: number; frames: number; tone: Tone; voice: Voice};

const f = (seconds: number) => Math.round(seconds * FPS);

export const SCENES: Scene[] = (() => {
  let from = 0;
  return SPECS.map((spec) => {
    const clip = clips[spec.id];
    const at = f(spec.voiceAt);
    const voice: Voice = {
      file: clip.file,
      at,
      frames: f(clip.duration),
      // v3 audio tags like [softly] come back as words; they aren't spoken.
      words: clip.words.filter((w) => !w.text.startsWith('[')).map((w) => ({text: w.text, from: at + f(w.start), to: at + f(w.end)})),
    };
    const frames = Math.max(spec.frames, f(spec.voiceAt + clip.duration + spec.tail));
    const scene = {id: spec.id, from, frames, tone: spec.tone, voice};
    from += frames - WIPE;
    return scene;
  });
})();

export const TOTAL_FRAMES = SCENES[SCENES.length - 1].from + SCENES[SCENES.length - 1].frames;

/** The frame where the narrator starts (or, with `end`, finishes) the first word starting with `text`. */
export const said = (voice: Voice, text: string, end = false, occurrence = 0): number => {
  const clean = (s: string) => s.toLowerCase().replace(/[^a-z0-9'-]/g, '');
  const matches = voice.words.filter((w) => clean(w.text).startsWith(text.toLowerCase()));
  const word = matches[occurrence] ?? matches[0];
  if (!word) throw new Error(`"${text}" isn't in the ${voice.file} line`);
  return end ? word.to : word.from;
};
