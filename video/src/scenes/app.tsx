import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
import {DISPLAY, MARGIN, MONO, type Tone} from '../theme';
import {said, type Voice} from '../timeline';
import {EASE, mix, pop, ramp} from '../motion';
import {Chapter, Crop, Em, Headline, Note, Sfx, Shot} from '../kit';

type Props = {tone: Tone; frames: number; voice: Voice};

// Screenshots are 1640×1440 (2×); rects below are in 1× points.
const ROW = {x: 228, w: 572};

/** Left-column captions that replace each other as the camera moves. */
const Captions: React.FC<{items: {at: number; text: React.ReactNode}[]; tone: Tone; top?: number; size?: number}> = ({items, tone, top = 340, size = 76}) => {
  const frame = useCurrentFrame();
  return (
    <div style={{position: 'absolute', left: MARGIN, top, width: 560}}>
      {items.map((item, i) => {
        const next = items[i + 1]?.at ?? Infinity;
        const t = ramp(frame, item.at, item.at + 20);
        const out = next === Infinity ? 0 : ramp(frame, next - 6, next + 8);
        if (t <= 0 || out >= 1) return null;
        return (
          <div key={i} style={{position: 'absolute', top: 0, fontFamily: DISPLAY, fontWeight: 300, fontSize: size, lineHeight: 1.06, letterSpacing: '-0.02em', color: tone.fg, opacity: t * (1 - out), transform: `translateY(${mix(36, 0, t) - 30 * out}px)`}}>
            {item.text}
          </div>
        );
      })}
    </div>
  );
};

export const Keys: React.FC<Props> = ({tone}) => {
  const steps = [
    {at: 22, rect: {...ROW, y: 52, h: 37}, text: <>Option, Command, <Em>or Fn.</Em></>},
    {at: 82, rect: {...ROW, y: 142, h: 37}, text: <>Or a <Em>mouse button.</Em></>},
    {at: 138, rect: {...ROW, y: 421, h: 36}, text: <>Tap once to go <Em>hands-free.</Em></>},
    {at: 192, rect: {...ROW, y: 260, h: 43}, text: <>Skip apps, <Em>like games.</Em></>},
  ];
  return (
    <AbsoluteFill>
      <Chapter n={6} title="Your key" tone={tone} />
      <Shot
        src="shots/settings-shortcut.png" w={820} h={720} tone={tone} center={{x: 1390, y: 560}}
        cams={[{at: 0, x: 514, y: 250, s: 1.0}, {at: 22, x: 514, y: 160, s: 1.2}, {at: 138, x: 514, y: 380, s: 1.15}, {at: 192, x: 514, y: 300, s: 1.15}]}
        spots={steps.map((s) => ({at: s.at, rect: s.rect}))}
      />
      <Captions items={steps} tone={tone} />
      <Note tone={tone} at={30} style={{position: 'absolute', left: MARGIN, top: 860, width: 600}}>
        a single key keeps working in password fields, where macOS blocks key combinations
      </Note>
      {steps.map((s) => (
        <Sfx key={s.at} at={s.at} name="tick" volume={0.2} />
      ))}
    </AbsoluteFill>
  );
};

export const Models: React.FC<Props> = ({tone, voice}) => {
  const frame = useCurrentFrame();
  const modelsAt = said(voice, 'seventy');
  const languagesAt = said(voice, 'twenty');
  const count = Math.round(interpolate(frame, [modelsAt, modelsAt + 26], [0, 72], {easing: EASE, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}));
  const languages = Math.round(interpolate(frame, [languagesAt, languagesAt + 22], [0, 25], {easing: EASE, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}));
  const a = ramp(frame, modelsAt - 8, modelsAt + 12);
  const b = ramp(frame, languagesAt - 8, languagesAt + 12);
  const stat = {fontFamily: DISPLAY, fontWeight: 300, fontSize: 210, lineHeight: 0.9, letterSpacing: '-0.05em', color: tone.fg, fontVariantNumeric: 'tabular-nums' as const};
  const label = {fontFamily: DISPLAY, fontWeight: 300, fontSize: 52, color: tone.fg, marginLeft: 18};
  return (
    <AbsoluteFill>
      <Chapter n={7} title="Models" tone={tone} />
      <Shot
        src="shots/settings-models.png" w={820} h={720} tone={tone} center={{x: 1410, y: 560}}
        cams={[{at: 0, x: 514, y: 220, s: 1.0}, {at: 30, x: 514, y: 180, s: 1.12}, {at: 110, x: 514, y: 320, s: 1.12}, {at: 175, x: 514, y: 470, s: 1.08}]}
        spots={[{at: 26, rect: {...ROW, y: 78, h: 130}}, {at: 110, rect: {...ROW, y: 265, h: 67}}, {at: 175, rect: {...ROW, y: 515, h: 200}}]}
      />
      <div style={{position: 'absolute', left: MARGIN, top: 290, opacity: a, transform: `translateY(${mix(30, 0, a)}px)`}}>
        <span style={stat}>{count}</span>
        <span style={label}>models</span>
      </div>
      <div style={{position: 'absolute', left: MARGIN, top: 520, opacity: b, transform: `translateY(${mix(30, 0, b)}px)`}}>
        <span style={stat}>{languages}</span>
        <span style={label}>languages</span>
      </div>
      <Note tone={tone} at={120} style={{position: 'absolute', left: MARGIN, top: 760, width: 560}}>
        25 with the default, Parakeet v3. Every model downloads once, pinned and checked, and runs on the Neural Engine or the GPU.
      </Note>
      {Array.from({length: 8}, (_, i) => (
        <Sfx key={i} at={modelsAt + i * 4} name="keytap" volume={0.12} />
      ))}
    </AbsoluteFill>
  );
};

export const Private: React.FC<Props> = ({tone}) => {
  const rows = [
    {at: 34, rect: {...ROW, y: 52, h: 37}},
    {at: 66, rect: {...ROW, y: 89, h: 37}},
    {at: 98, rect: {...ROW, y: 126, h: 52}},
    {at: 130, rect: {...ROW, y: 178, h: 38}},
    {at: 168, rect: {...ROW, y: 271, h: 128}},
  ];
  return (
    <AbsoluteFill>
      <Chapter n={10} title="Private" tone={tone} />
      <Shot
        src="shots/settings-privacy.png" w={820} h={720} tone={tone} center={{x: 1370, y: 560}}
        cams={[{at: 0, x: 514, y: 230, s: 1.1}, {at: 34, x: 514, y: 150, s: 1.3}, {at: 168, x: 514, y: 280, s: 1.25}]}
        spots={rows}
      />
      <Headline at={10} tone={tone} size={124} lines={['Nothing', 'leaves', <>your <Em>Mac.</Em></>]} style={{position: 'absolute', left: MARGIN, top: 290}} />
      <Note tone={tone} at={60} style={{position: 'absolute', left: MARGIN, top: 760, width: 560}}>
        checked with lsof: no network connections after the model download
      </Note>
      {rows.map((r) => (
        <Sfx key={r.at} at={r.at} name="tick" volume={0.18} />
      ))}
    </AbsoluteFill>
  );
};

const CARDS = [
  {src: 'shots/transcribe-file.png', rect: {x: 0, y: 0, w: 560, h: 452}, scale: 0.62, imageWidth: 560, text: <>Transcribe any <Em>audio or video</Em> file.</>},
  {src: 'shots/settings-general-0.55.png', rect: {x: 228, y: 190, w: 572, h: 166}, scale: 0.68, text: <>Live text over the pill, <Em>top or bottom.</Em></>},
  {src: 'shots/settings-general-1.0.png', rect: {x: 228, y: 208, w: 500, h: 92}, scale: 0.78, text: <>Your music <Em>turns down</Em> while you talk.</>},
  {src: 'shots/settings-privacy.png', rect: {x: 228, y: 271, w: 572, h: 128}, scale: 0.68, text: <>History, kept as long <Em>as you choose.</Em></>},
];

export const More: React.FC<Props> = ({tone}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill>
      <Chapter n={11} title="And more" tone={tone} />
      <div style={{position: 'absolute', left: MARGIN, top: 250, right: MARGIN, display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 44, alignItems: 'start'}}>
        {CARDS.map((card, i) => {
          const at = 16 + i * 30;
          const show = pop(frame, at, 20, 0.8);
          return (
            <div key={i} style={{opacity: show, transform: `translateY(${mix(50, 0, show)}px)`}}>
              <div style={{height: 300, display: 'flex', alignItems: 'flex-end'}}>
                <Crop src={card.src} rect={card.rect} scale={card.scale} imageWidth={card.imageWidth} />
              </div>
              <div style={{marginTop: 34, height: 1, background: tone.faint}} />
              <div style={{marginTop: 22, fontFamily: MONO, fontSize: 18, color: tone.accent, letterSpacing: '0.14em'}}>{String(i + 1).padStart(2, '0')}</div>
              <div style={{marginTop: 10, fontFamily: DISPLAY, fontWeight: 300, fontSize: 44, lineHeight: 1.1, letterSpacing: '-0.015em', color: tone.fg}}>{card.text}</div>
            </div>
          );
        })}
      </div>
      <Note tone={tone} at={150} style={{position: 'absolute', left: MARGIN, top: 880}}>
        plus: launch at login · pick any microphone · Esc cancels · the last transcript is always in the menu
      </Note>
      {CARDS.map((_, i) => (
        <Sfx key={i} at={16 + i * 30} name="tick" volume={0.2} />
      ))}
    </AbsoluteFill>
  );
};
