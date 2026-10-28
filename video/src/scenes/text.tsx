import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {APP, DISPLAY, MARGIN, MONO, UI, type Tone} from '../theme';
import {said, type Voice} from '../timeline';
import {mix, pop, ramp} from '../motion';
import {AppWindow, Chapter, Crop, Em, Headline, Line, Note, Pill, Sfx, Strike} from '../kit';

type Props = {tone: Tone; frames: number; voice: Voice};

// Sotto's real output (TextCleanup, then SelfCorrection):
// "Um, let's meet at 2, actually 3." → "Let's meet at 3."
const TOKENS: {text: string; cut?: 'filler' | 'correction'; becomes?: string}[] = [
  {text: 'Um,', cut: 'filler'},
  {text: "let's", becomes: "Let's"},
  {text: 'meet'},
  {text: 'at'},
  {text: '2,', cut: 'correction'},
  {text: 'actually', cut: 'correction'},
  {text: '3.'},
];

export const Clean: React.FC<Props> = ({tone, voice}) => {
  const frame = useCurrentFrame();
  // Strikes land as the narrator names them; the cuts close on "gone".
  const fillerAt = said(voice, 'ums');
  const correctionAt = said(voice, 'two');
  const done = said(voice, 'gone') + 6;
  const label = ramp(frame, done - 6, done + 6);
  const crop = pop(frame, done + 14, 20, 0.8);
  return (
    <AbsoluteFill>
      <Chapter n={2} title="Clean" tone={tone} />
      <div style={{position: 'absolute', left: MARGIN, top: 300, fontFamily: MONO, fontSize: 20, letterSpacing: '0.16em', textTransform: 'uppercase', height: 30}}>
        <span style={{position: 'absolute', whiteSpace: 'nowrap', color: tone.dim, opacity: 1 - label}}>You say</span>
        <span style={{position: 'absolute', whiteSpace: 'nowrap', color: tone.accent, opacity: label}}>Sotto types</span>
      </div>
      <div style={{position: 'absolute', left: MARGIN, top: 360, fontFamily: DISPLAY, fontWeight: 300, fontSize: 118, letterSpacing: '-0.025em', color: tone.fg, whiteSpace: 'nowrap', display: 'flex'}}>
        {TOKENS.map((token, i) => {
          const shown = ramp(frame, 8 + i * 3, 26 + i * 3);
          const cutAt = token.cut === 'filler' ? fillerAt : correctionAt;
          const strike = token.cut ? ramp(frame, cutAt, cutAt + 12) : 0;
          const gone = token.cut ? ramp(frame, done - 22, done) : 0;
          const swap = token.becomes ? ramp(frame, done - 22, done) : 0;
          const width = token.text.length * 0.42 * 118;
          return (
            <span key={i} style={{position: 'relative', display: 'inline-block', overflow: 'visible', maxWidth: token.cut ? (width + 40) * (1 - gone) : undefined, opacity: shown * (1 - gone), marginRight: `${0.24 * (1 - gone)}em`, transform: `translateY(${mix(40, 0, shown)}px)`}}>
              <span style={{color: strike > 0.6 ? tone.dim : tone.fg}}>{swap > 0.5 && token.becomes ? token.becomes : token.text}</span>
              {token.cut ? <Strike t={strike} width={width} seed={`s${i}`} /> : null}
            </span>
          );
        })}
      </div>
      <Note tone={tone} at={done + 6} style={{position: 'absolute', left: MARGIN, top: 580}}>
        filler words out · spoken corrections fixed · nothing else changes
      </Note>
      <div style={{position: 'absolute', left: MARGIN, top: 730, opacity: crop, transform: `translateY(${mix(40, 0, crop)}px)`}}>
        <Crop src="shots/settings-general.png" rect={{x: 228, y: 173, w: 572, h: 104}} scale={1.5} />
      </div>
      <Note tone={tone} at={done + 26} style={{position: 'absolute', left: MARGIN + 900, top: 790}}>
        Settings → General
        <br />
        on by default, each one optional
      </Note>
      <Sfx at={fillerAt} name="tick" volume={0.5} />
      <Sfx at={correctionAt} name="tick" volume={0.5} />
      <Sfx at={done} name="pop" volume={0.25} />
    </AbsoluteFill>
  );
};

// Real Styles.apply output: casual drops the capital and final period,
// plain also drops the trailing space; standard keeps proper sentences.
const STYLES = [
  {app: 'Messages', text: 'sounds good, see you at 3', note: 'casual: no capital, no period', mono: false},
  {app: 'Mail', text: 'Sounds good, see you at 3.', note: 'standard: full sentences', mono: false},
  {app: 'Terminal', text: 'git status', note: 'plain: no trailing space', mono: true},
];

export const Style: React.FC<Props> = ({tone, voice}) => {
  const frame = useCurrentFrame();
  const appear = [said(voice, 'casual'), said(voice, 'proper'), said(voice, 'proper') + 26];
  const crop = pop(frame, appear[2] + 30, 20, 0.8);
  return (
    <AbsoluteFill>
      <Chapter n={3} title="Style" tone={tone} />
      <Headline at={8} tone={tone} size={96} lines={['Written the way', <>each app <Em>expects.</Em></>]} style={{position: 'absolute', left: MARGIN, top: 200}} />
      <div style={{position: 'absolute', left: MARGIN, top: 470, display: 'flex', gap: 50}}>
        {STYLES.map((s, i) => {
          const at = appear[i];
          const show = pop(frame, at - 14, 20, 0.8);
          const typed = frame >= at;
          return (
            <div key={s.app} style={{opacity: show, transform: `translateY(${mix(40, 0, show)}px)`}}>
              <AppWindow title={s.app} width={505} height={220}>
                <div style={{padding: '30px 28px', fontFamily: s.mono ? "'SF Mono', Menlo, monospace" : UI, fontSize: 24, color: APP.fg}}>
                  {s.mono ? <span style={{color: APP.fg2}}>~ % </span> : null}
                  <span style={{background: typed ? `rgba(10,132,255,${0.3 * (1 - ramp(frame, at, at + 30))})` : 'transparent', borderRadius: 4}}>{typed ? s.text : ''}</span>
                </div>
              </AppWindow>
              <Note tone={tone} at={at + 6} style={{marginTop: 18}}>{s.note}</Note>
            </div>
          );
        })}
      </div>
      <div style={{position: 'absolute', left: MARGIN, top: 840, opacity: crop, transform: `translateY(${mix(30, 0, crop)}px)`}}>
        <Crop src="shots/settings-general-1.0.png" rect={{x: 228, y: 395, w: 500, h: 63}} scale={1.5} />
      </div>
      <Note tone={tone} at={appear[2] + 42} style={{position: 'absolute', left: MARGIN + 900, top: 850}}>
        only capitals, the final period and the
        <br />
        trailing space change, never your words
      </Note>
      {appear.map((at, i) => (
        <Sfx key={i} at={at} name="tick" volume={0.4} />
      ))}
    </AbsoluteFill>
  );
};

const LIVE = ['Yes!', 'See', 'you', 'at', '3.', 'Send', 'it.'];
// TextRules.stripSendPhrase: "Yes! See you at 3. Send it." → "Yes! See you at 3." + Return.
const SENT = 'Yes! See you at 3.';

export const Send: React.FC<Props> = ({tone, voice}) => {
  const frame = useCurrentFrame();
  // The user dictates first; "Send it." comes in the narrator's voice.
  const keyDown = 12;
  const LIVE_AT = [22, 31, 38, 45, 52, said(voice, 'send'), said(voice, 'it')];
  const release = said(voice, 'it', true) + 4;
  const returnAt = said(voice, 'return');
  const live = LIVE.filter((_, i) => frame >= LIVE_AT[i]).join(' ');
  const pill = frame < release ? pop(frame, keyDown, 16) : 1 - ramp(frame, release, release + 8);
  const sent = pop(frame, returnAt, 16);
  const win = pop(frame, 0, 24, 0.9);
  const crop = pop(frame, returnAt + 30, 20, 0.8);
  return (
    <AbsoluteFill>
      <Chapter n={4} title="Send" tone={tone} />
      <div style={{position: 'absolute', left: MARGIN, top: 280, fontFamily: DISPLAY, fontWeight: 300, fontSize: 104, lineHeight: 1.06, letterSpacing: '-0.025em', color: tone.fg}}>
        <Line at={10}>End with</Line>
        <Line at={LIVE_AT[5]}><Em>“send it,”</Em></Line>
        <Line at={returnAt}>it presses Return.</Line>
      </div>
      <div style={{position: 'absolute', left: 1010, top: 180, opacity: win, transform: `translateX(${mix(80, 0, win)}px)`}}>
        <AppWindow title="Chat" width={760} height={540}>
          <div style={{position: 'absolute', inset: 0, padding: '24px 28px 96px', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', gap: 12}}>
            <div style={{fontSize: 12, color: '#6E6E73', textAlign: 'center'}}>Today 14:02</div>
            <Bubble mine={false}>Are we still on for today?</Bubble>
            <div style={{alignSelf: 'flex-end', opacity: sent, transform: `translateY(${mix(64, 0, sent)}px)`}}>
              <Bubble mine>{SENT}</Bubble>
            </div>
          </div>
          <div style={{position: 'absolute', left: 20, right: 20, bottom: 20, height: 48, borderRadius: 24, border: `1px solid ${APP.winRing}`, display: 'flex', alignItems: 'center', padding: '0 20px', fontSize: 17, color: frame >= release && frame < returnAt ? APP.fg : '#6E6E73'}}>
            {frame >= release && frame < returnAt ? SENT : 'Message'}
          </div>
        </AppWindow>
      </div>
      <div style={{position: 'absolute', left: 1010, width: 760, top: 760, display: 'flex', justifyContent: 'center'}}>
        <Pill show={pill} speaking={frame >= 18 && frame < release - 2 ? 1 : 0.1} text={live || undefined} seconds={(Math.min(frame, release) - keyDown) / 30} scale={1.2} />
      </div>
      <div style={{position: 'absolute', left: MARGIN, top: 760, opacity: crop, transform: `translateY(${mix(30, 0, crop)}px)`}}>
        <Crop src="shots/settings-general.png" rect={{x: 228, y: 280, w: 572, h: 52}} scale={1.3} />
        <Note tone={tone} at={returnAt + 42} style={{marginTop: 22}}>or always send, with Return or ⌘ Return, in apps you choose</Note>
      </div>
      <Sfx at={keyDown} name="keydown" volume={0.55} />
      <Sfx at={keyDown + 2} name="pop" volume={0.25} />
      <Sfx at={release} name="keyup" volume={0.55} />
      <Sfx at={returnAt} name="thunk" volume={0.8} />
    </AbsoluteFill>
  );
};

const Bubble: React.FC<{mine: boolean; children: React.ReactNode}> = ({mine, children}) => (
  <div style={{alignSelf: mine ? 'flex-end' : 'flex-start', padding: '10px 16px', borderRadius: 20, fontSize: 18, background: mine ? APP.accent : '#2C2C30', color: '#FFFFFF'}}>{children}</div>
);

// Real CustomWords and TextRules output for these inputs.
const WORDS = [
  {kind: 'Custom word', said: 'furcan', wrote: 'Furkan', at: 24},
  {kind: 'Custom word', said: 'chat g p t', wrote: 'ChatGPT', at: 60},
  {kind: 'Replacement', said: 'gee mail', wrote: 'Gmail', at: 96},
  {kind: 'Snippet', said: 'my address', wrote: '221B Baker Street', at: 132},
];

export const Words: React.FC<Props> = ({tone}) => {
  const frame = useCurrentFrame();
  const panel = pop(frame, 196, 18, 0.8);
  return (
    <AbsoluteFill>
      <Chapter n={5} title="Your words" tone={tone} />
      <div style={{position: 'absolute', left: MARGIN, top: 220, display: 'flex', flexDirection: 'column', gap: 34}}>
        {WORDS.map((w) => {
          const said = ramp(frame, w.at, w.at + 14);
          const arrow = ramp(frame, w.at + 12, w.at + 26);
          return (
            <div key={w.said} style={{display: 'flex', alignItems: 'baseline', height: 104}}>
              <span style={{width: 250, fontFamily: MONO, fontSize: 18, letterSpacing: '0.14em', textTransform: 'uppercase', color: tone.accent, opacity: said}}>{w.kind}</span>
              <span style={{width: 430, fontFamily: MONO, fontSize: 40, color: tone.dim, opacity: said}}>“{w.said}”</span>
              <svg width={110} height={20} style={{alignSelf: 'center', overflow: 'visible'}}>
                <line x1={0} y1={10} x2={90 * arrow} y2={10} stroke={tone.fg} strokeWidth={1.5} />
                {arrow > 0.95 ? <path d="M82 3 L92 10 L82 17" fill="none" stroke={tone.fg} strokeWidth={1.5} /> : null}
              </svg>
              <div style={{marginLeft: 30, fontFamily: DISPLAY, fontWeight: 300, fontSize: 84, letterSpacing: '-0.02em', color: tone.fg, whiteSpace: 'nowrap'}}>
                <Line at={w.at + 20}>{w.wrote}</Line>
              </div>
            </div>
          );
        })}
      </div>
      <div style={{position: 'absolute', left: MARGIN, top: 900, display: 'flex', alignItems: 'center', gap: 40, opacity: panel, transform: `translateY(${mix(30, 0, panel)}px)`}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 14, height: 54, padding: '0 14px 0 20px', borderRadius: 27, background: APP.win, boxShadow: '0 20px 50px rgba(0,0,0,0.35)', fontFamily: UI, fontSize: 17, color: APP.fg}}>
          <svg width={18} height={18} viewBox="0 0 18 18" aria-hidden="true"><path d="M3 2.5h9.5a2 2 0 0 1 2 2V16H5a2 2 0 0 1-2-2z M3 13.5a2 2 0 0 1 2-2h9.5" fill="none" stroke={APP.fg2} strokeWidth={1.4} /></svg>
          <span>Add <b>Furkan</b> to your dictionary?</span>
          <span style={{padding: '5px 14px', borderRadius: 8, background: APP.accent, fontSize: 15, fontWeight: 600}}>Add</span>
          <span style={{color: APP.fg2, fontSize: 15, padding: '0 6px'}}>✕</span>
        </div>
        <Note tone={tone} at={206}>fix a word by hand once, and Sotto offers to learn it</Note>
      </div>
      {WORDS.map((w) => (
        <Sfx key={w.said} at={w.at + 20} name="tick" volume={0.35} />
      ))}
      <Sfx at={196} name="pop" volume={0.25} />
    </AbsoluteFill>
  );
};
