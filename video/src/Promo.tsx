import React from 'react';
import {AbsoluteFill, Audio, Sequence, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {EASE} from './motion';
import {SCENES, TOTAL_FRAMES, WIPE, type Scene, type SceneId, type Voice} from './timeline';
import type {Tone} from './theme';
import {Grain, Ground, Sfx, ToneContext} from './kit';
import {Dictate, Hook, Open} from './scenes/intro';
import {Clean, Send, Style, Words} from './scenes/text';
import {Keys, Models, More, Private} from './scenes/app';
import {Battery, Quiet} from './scenes/numbers';
import {End} from './scenes/end';

const VIEWS: Record<SceneId, React.FC<{tone: Tone; frames: number; voice: Voice}>> = {
  open: Open,
  hook: Hook,
  dictate: Dictate,
  clean: Clean,
  style: Style,
  send: Send,
  words: Words,
  keys: Keys,
  models: Models,
  quiet: Quiet,
  battery: Battery,
  private: Private,
  more: More,
  end: End,
};

/** Each scene after the first wipes in from the right over the last one. */
const Wipe: React.FC<{scene: Scene; first: boolean; children: React.ReactNode}> = ({scene, first, children}) => {
  const frame = useCurrentFrame();
  const t = first ? 1 : EASE(Math.min(1, Math.max(0, frame / WIPE)));
  const out = Math.min(1, Math.max(0, (frame - (scene.frames - WIPE)) / WIPE));
  return (
    <AbsoluteFill style={{clipPath: `inset(0 0 0 ${(1 - t) * 100}%)`}}>
      <AbsoluteFill style={{transform: `translateX(${(1 - t) * 120 - out * 60}px)`}}>{children}</AbsoluteFill>
    </AbsoluteFill>
  );
};

// When the narrator speaks, in whole-video frames, so the bed can dip under him.
const SPEECH = SCENES.map((s) => [s.from + s.voice.at, s.from + s.voice.at + s.voice.frames] as const);

const bedVolume = (frame: number) => {
  const fade = interpolate(frame, [0, 45, TOTAL_FRAMES - 75, TOTAL_FRAMES], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const near = Math.min(...SPEECH.map(([a, b]) => (frame < a ? a - frame : frame > b ? frame - b : 0)));
  const duck = interpolate(near, [0, 12], [0.45, 1], {extrapolateRight: 'clamp'});
  return 0.32 * fade * duck;
};

export const Promo: React.FC = () => (
  <AbsoluteFill style={{background: '#000'}}>
    <Audio src={staticFile('sfx/bed.wav')} volume={bedVolume} />
    {SCENES.map((scene, index) => {
      const View = VIEWS[scene.id];
      return (
        <Sequence key={scene.id} from={scene.from} durationInFrames={scene.frames} name={scene.id}>
          <ToneContext.Provider value={scene.tone}>
            <Wipe scene={scene} first={index === 0}>
              <Ground tone={scene.tone} />
              <View tone={scene.tone} frames={scene.frames} voice={scene.voice} />
            </Wipe>
          </ToneContext.Provider>
          <Sequence from={scene.voice.at} durationInFrames={scene.voice.frames + 10} name={`voice: ${scene.id}`} layout="none">
            <Audio src={staticFile(scene.voice.file)} />
          </Sequence>
          {index > 0 ? <Sfx at={0} name="whoosh" volume={0.3} /> : null}
        </Sequence>
      );
    })}
    <Grain />
  </AbsoluteFill>
);
