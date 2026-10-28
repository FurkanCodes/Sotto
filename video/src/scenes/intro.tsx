import React from 'react';
import {AbsoluteFill, random, useCurrentFrame} from 'remotion';
import {APP, DISPLAY, MARGIN, MARKING, MONO, UI, type Tone} from '../theme';
import {mix, pop, ramp} from '../motion';
import {said, type Voice} from '../timeline';
import {AppWindow, Caret, Chapter, Em, Headline, Key, Line, Note, Pill, Sfx, Staff} from '../kit';

type Props = {tone: Tone; frames: number; voice: Voice};

/** "sotto voce" set like a marking in a score, over a voice that quiets to pp. */
export const Open: React.FC<Props> = ({tone, voice}) => {
  const frame = useCurrentFrame();
  const staffY = 560;
  const mid = staffY + 28;
  const head = mix(MARGIN, 1920 - MARGIN, ramp(frame, 12, 150));
  const points: string[] = [];
  for (let x = MARGIN; x <= head; x += 3) {
    const u = (x - MARGIN) / (1920 - 2 * MARGIN);
    const amp = 34 * Math.pow(Math.sin(Math.PI * Math.min(1, u * 1.15)), 2) * (1 - 0.75 * u);
    points.push(`${x},${mid + amp * Math.sin(x / 7 + frame / 3) * (0.6 + 0.4 * Math.sin(x / 31))}`);
  }
  return (
    <AbsoluteFill>
      <Staff t={ramp(frame, 0, 50)} y={staffY} color={tone.faint} />
      <svg width={1920} height={1080} style={{position: 'absolute', inset: 0}}>
        <polyline points={points.join(' ')} fill="none" stroke={tone.fg} strokeWidth={1.6} strokeLinejoin="round" opacity={0.85} />
      </svg>
      <div style={{position: 'absolute', left: MARGIN, top: 300, fontFamily: MARKING, fontStyle: 'italic', fontWeight: 300, fontSize: 168, letterSpacing: '-0.02em', color: tone.fg}}>
        <Line at={said(voice, 'sotto') - 4} dur={30}>sotto voce</Line>
      </div>
      <Note tone={tone} at={said(voice, 'italian') - 6} style={{position: 'absolute', left: MARGIN + 6, top: 680}}>
        sot·to vo·ce &nbsp;(Italian) &nbsp;— in a quiet voice; under the breath.
      </Note>
      <div style={{position: 'absolute', right: MARGIN, top: staffY + 84, fontFamily: MARKING, fontStyle: 'italic', fontWeight: 400, fontSize: 64, color: tone.accent, opacity: ramp(frame, said(voice, 'quietly'), said(voice, 'quietly') + 16)}}>pp</div>
      <Sfx at={said(voice, 'sotto') - 4} name="rise" volume={0.18} />
    </AbsoluteFill>
  );
};

// Typing the hook by hand: slow, with one typo. Each entry is a keystroke.
const KEYS = [...'You think fsa', '⌫', '⌫', ...'aster th'];
const keystrokes = (() => {
  let at = 30;
  return KEYS.map((key, i) => {
    at += 5 + Math.floor(random(`k${i}`) * 7);
    return {key, at};
  });
})();

export const Hook: React.FC<Props> = ({tone, voice}) => {
  const frame = useCurrentFrame();
  let typed = '';
  for (const {key, at} of keystrokes) {
    if (frame < at) break;
    typed = key === '⌫' ? typed.slice(0, -1) : typed + key;
  }
  return (
    <AbsoluteFill>
      <Headline at={said(voice, 'think') - 4} tone={tone} size={150} lines={['You think faster', <>than you <Em>type.</Em></>]} style={{position: 'absolute', left: MARGIN, top: 250}} />
      <div style={{position: 'absolute', left: MARGIN, top: 700, width: 980, opacity: ramp(frame, 18, 34)}}>
        <div style={{fontFamily: UI, fontSize: 46, color: tone.fg, height: 64}}>
          {typed}
          <Caret height={44} color={tone.accent} />
        </div>
        <div style={{height: 1, background: tone.faint, marginTop: 10}} />
      </div>
      {keystrokes.map(({at}, i) => (
        <Sfx key={i} at={at} name="keytap" volume={0.35} />
      ))}
    </AbsoluteFill>
  );
};

const SENTENCE = "Let's move the launch to Thursday and tell the team today.".split(' ');

export const Dictate: React.FC<Props> = ({tone, voice}) => {
  const frame = useCurrentFrame();
  // The key goes down on "hold", up on "let go".
  const keyDown = said(voice, 'hold') - 2;
  const release = said(voice, 'go', true);
  const firstWord = keyDown + 12;
  const step = (release - 10 - firstWord) / SENTENCE.length;
  const spoken = SENTENCE.filter((_, i) => frame >= firstWord + i * step).join(' ');
  const speaking = frame >= firstWord - 4 && frame < release - 6 ? 1 : 0.15;
  const pressed = frame >= keyDown && frame < release ? 1 : 0;
  const pill = frame < release ? pop(frame, keyDown, 16) : 1 - ramp(frame, release, release + 8);
  const landed = frame >= release + 2;
  const glow = 1 - ramp(frame, release + 2, release + 50);
  const win = pop(frame, 0, 24, 0.9);
  const measure = ramp(frame, said(voice, "that's") - 4, said(voice, "that's") + 20);

  return (
    <AbsoluteFill>
      <Chapter n={1} title="Hold, speak, let go" tone={tone} />
      <div style={{position: 'absolute', left: MARGIN, top: 280, fontFamily: DISPLAY, fontWeight: 300, fontSize: 112, lineHeight: 1.02, letterSpacing: '-0.035em', color: tone.fg}}>
        <Line at={keyDown - 4}>Hold a key.</Line>
        <Line at={said(voice, 'say') - 4}>Speak.</Line>
        <Line at={release - 6}><Em>Let go.</Em></Line>
      </div>
      <div style={{position: 'absolute', left: MARGIN, top: 750}}>
        <Key glyph="⌥" label="option" down={pressed} />
        <Note tone={tone} style={{marginTop: 18}}>right option</Note>
      </div>

      <div style={{position: 'absolute', left: 820, top: 200, opacity: win, transform: `translateX(${mix(80, 0, win)}px)`}}>
        <AppWindow title="Notes" width={960} height={480}>
          <div style={{padding: '34px 54px', display: 'flex', flexDirection: 'column', gap: 14}}>
            <div style={{fontSize: 30, fontWeight: 700}}>Launch plan</div>
            <div style={{fontSize: 14, color: APP.fg2}}>Wednesday, 28 October</div>
            <div style={{fontSize: 20, lineHeight: 1.6}}>Open items: the model picker and the first-run screen.</div>
            <div style={{fontSize: 20, lineHeight: 1.6}}>
              {landed ? <span style={{background: `rgba(10,132,255,${0.32 * glow})`, borderRadius: 4, padding: '1px 2px'}}>{SENTENCE.join(' ')}</span> : null}
              <Caret />
            </div>
          </div>
          <div style={{position: 'absolute', left: 0, right: 0, bottom: 34, display: 'flex', justifyContent: 'center'}}>
            <Pill show={pill} speaking={speaking} text={spoken || undefined} seconds={(Math.min(frame, release) - keyDown) / 30} scale={1.15} />
          </div>
        </AppWindow>
      </div>

      <div style={{position: 'absolute', left: 820, top: 730, display: 'flex', alignItems: 'baseline', gap: 26, opacity: measure, transform: `translateY(${mix(14, 0, measure)}px)`}}>
        <span style={{fontFamily: DISPLAY, fontWeight: 300, fontSize: 92, letterSpacing: '-0.04em', color: tone.fg}}>117 ms</span>
        <span style={{fontFamily: MONO, fontSize: 21, color: tone.dim, lineHeight: 1.45}}>
          from key up to text on screen
          <br />
          measured in the app, real mic, Apple M5
        </span>
      </div>

      <Sfx at={keyDown} name="keydown" volume={0.7} />
      <Sfx at={keyDown + 3} name="pop" volume={0.3} />
      <Sfx at={release} name="keyup" volume={0.7} />
      <Sfx at={release + 3} name="tick" volume={0.45} />
    </AbsoluteFill>
  );
};
