import React from 'react';
import {AbsoluteFill, Audio, Img, Sequence, interpolate, random, staticFile, useCurrentFrame} from 'remotion';
import {APP, DISPLAY, FPS, MARGIN, MONO, UI, onInk, type Tone} from './theme';

/** The current scene's tone, so small pieces can take its accent. */
export const ToneContext = React.createContext<Tone>(onInk);
const useAccent = () => React.useContext(ToneContext).accent;
import {EASE, mix, ramp} from './motion';

/** Film grain: animated noise, changing every other frame. */
export const Grain: React.FC<{strength?: number}> = ({strength = 0.07}) => {
  const frame = useCurrentFrame();
  const seed = Math.floor(frame / 2) % 50;
  return (
    <AbsoluteFill style={{pointerEvents: 'none', mixBlendMode: 'overlay', opacity: strength * 4}}>
      <svg width="100%" height="100%">
        <filter id={`grain-${seed}`}>
          <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves={2} seed={seed} stitchTiles="stitch" />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <rect width="100%" height="100%" filter={`url(#grain-${seed})`} opacity={0.25} />
      </svg>
    </AbsoluteFill>
  );
};

/** A scene's ground, with a soft vignette so it reads as lit, not flat. */
export const Ground: React.FC<{tone: Tone}> = ({tone}) => (
  <AbsoluteFill style={{background: tone.bg}}>
    <AbsoluteFill style={{background: 'radial-gradient(130% 100% at 50% 45%, transparent 55%, rgba(0,0,0,0.28))'}} />
  </AbsoluteFill>
);

/** Five staff lines, drawn on from the left as `t` goes 0 → 1. */
export const Staff: React.FC<{t: number; y: number; color: string; gap?: number; left?: number; right?: number}> = ({t, y, color, gap = 14, left = MARGIN, right = MARGIN}) => (
  <svg width={1920} height={1080} style={{position: 'absolute', inset: 0}}>
    {[0, 1, 2, 3, 4].map((i) => {
      const local = Math.min(1, Math.max(0, t * 1.25 - i * 0.06));
      return <line key={i} x1={left} x2={left + (1920 - left - right) * local} y1={y + i * gap} y2={y + i * gap} stroke={color} strokeWidth={1.2} />;
    })}
  </svg>
);

/** One line of type that slides up out of a mask. */
export const Line: React.FC<{at: number; children: React.ReactNode; style?: React.CSSProperties; dur?: number}> = ({at, children, style, dur = 22}) => {
  const frame = useCurrentFrame();
  const t = ramp(frame, at, at + dur);
  return (
    <div style={{overflow: 'hidden', paddingBottom: '0.12em', marginBottom: '-0.12em', ...style}}>
      <div style={{transform: `translateY(${(1 - t) * 108}%)`}}>{children}</div>
    </div>
  );
};

/** A large serif headline, one entry per line. */
export const Headline: React.FC<{at: number; lines: React.ReactNode[]; tone: Tone; size?: number; stagger?: number; style?: React.CSSProperties}> = ({at, lines, tone, size = 128, stagger = 8, style}) => (
  <div style={{fontFamily: DISPLAY, fontWeight: 300, fontSize: size, lineHeight: 1.0, letterSpacing: '-0.035em', color: tone.fg, ...style}}>
    {lines.map((line, i) => (
      <Line key={i} at={at + i * stagger}>{line}</Line>
    ))}
  </div>
);

export const Em: React.FC<{children: React.ReactNode; color?: string}> = ({children, color}) => {
  const accent = useAccent();
  return <span style={{color: color ?? accent, fontWeight: 400}}>{children}</span>;
};

/** Small mono annotation text. */
export const Note: React.FC<{children: React.ReactNode; tone: Tone; at?: number; style?: React.CSSProperties}> = ({children, tone, at = 0, style}) => {
  const frame = useCurrentFrame();
  const t = ramp(frame, at, at + 16);
  return <div style={{fontFamily: MONO, fontSize: 22, lineHeight: 1.5, letterSpacing: '0.02em', color: tone.dim, opacity: t, transform: `translateY(${mix(8, 0, t)}px)`, ...style}}>{children}</div>;
};

/** "03 — Style": the chapter mark, top left, with a short rule that draws on. */
export const Chapter: React.FC<{n: number; title: string; tone: Tone}> = ({n, title, tone}) => {
  const frame = useCurrentFrame();
  const t = ramp(frame, 4, 26);
  return (
    <div style={{position: 'absolute', left: MARGIN, top: 96, display: 'flex', alignItems: 'center', gap: 18, fontFamily: MONO, fontSize: 20, letterSpacing: '0.16em', textTransform: 'uppercase', color: tone.dim, opacity: Math.min(1, t * 2)}}>
      <span style={{color: tone.accent}}>{String(n).padStart(2, '0')}</span>
      <span style={{display: 'inline-block', height: 1, width: 56 * t, background: tone.dim}} />
      <span>{title}</span>
    </div>
  );
};

type Rect = {x: number; y: number; w: number; h: number};
export type Cam = {at: number; x: number; y: number; s: number};
export type Spot = {at: number; rect: Rect | null};
export type Callout = {at: number; x: number; y: number; text: React.ReactNode; dx?: number; dy?: number};

const lerpKeys = <K extends {at: number}>(frame: number, keys: K[], get: (k: K) => number) => {
  if (keys.length === 1) return get(keys[0]);
  return interpolate(frame, keys.map((k) => k.at), keys.map(get), {easing: EASE, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
};

/**
 * A real screenshot of Sotto (captured at 2×, laid out at 1×), filmed by a
 * camera that moves between keyframes. A spotlight dims everything but one
 * row, and callouts draw a leader line from a point on the shot to a label.
 */
export const Shot: React.FC<{
  src: string; w: number; h: number; cams: Cam[]; spots?: Spot[]; callouts?: Callout[];
  center?: {x: number; y: number}; tone: Tone; show?: number;
}> = ({src, w, h, cams, spots = [], callouts = [], center = {x: 960, y: 540}, tone, show = 1}) => {
  const frame = useCurrentFrame();
  const x = lerpKeys(frame, cams, (c) => c.x);
  const y = lerpKeys(frame, cams, (c) => c.y);
  const s = lerpKeys(frame, cams, (c) => c.s);
  const left = center.x - x * s;
  const top = center.y - y * s;

  // The spotlight eases from one rect to the next; null turns it off.
  const active = [...spots].reverse().find((sp) => frame >= sp.at);
  const index = active ? spots.indexOf(active) : -1;
  const prev = index > 0 ? spots[index - 1].rect : null;
  const k = active ? ramp(frame, active.at, active.at + 14) : 0;
  const target = active?.rect ?? null;
  const from = prev ?? target;
  const rect = target && from ? {x: mix(from.x, target.x, k), y: mix(from.y, target.y, k), w: mix(from.w, target.w, k), h: mix(from.h, target.h, k)} : prev;
  const dim = target ? (prev ? 1 : k) : prev ? 1 - k : 0;

  return (
    <AbsoluteFill style={{opacity: show}}>
      <div style={{position: 'absolute', left, top, width: w * s, height: h * s, borderRadius: 12 * s, overflow: 'hidden', boxShadow: `0 ${40 * s}px ${90 * s}px rgba(0,0,0,0.45), 0 0 0 1px rgba(0,0,0,0.4)`}}>
        <Img src={staticFile(src)} style={{width: '100%', height: '100%', display: 'block'}} />
        {rect ? (
          <div style={{position: 'absolute', left: rect.x * s, top: rect.y * s, width: rect.w * s, height: rect.h * s, borderRadius: 10 * s, boxShadow: `0 0 0 ${4000}px rgba(4,9,14,${0.62 * dim})`}}>
            <div style={{position: 'absolute', inset: 0, borderRadius: 10 * s, border: `2px solid ${tone.accent}`, opacity: dim}} />
          </div>
        ) : null}
      </div>
      {callouts.map((c, i) => {
        const t = ramp(frame, c.at, c.at + 20);
        if (t <= 0) return null;
        const px = left + c.x * s;
        const py = top + c.y * s;
        const qx = px + (c.dx ?? 160);
        const qy = py + (c.dy ?? 0);
        const len = Math.hypot(qx - px, qy - py);
        return (
          <React.Fragment key={i}>
            <svg width={1920} height={1080} style={{position: 'absolute', inset: 0, overflow: 'visible'}}>
              <circle cx={px} cy={py} r={5 * Math.min(1, t * 3)} fill={tone.accent} />
              <line x1={px} y1={py} x2={mix(px, qx, t)} y2={mix(py, qy, t)} stroke={tone.accent} strokeWidth={1.5} strokeDasharray={len} />
            </svg>
            <div style={{position: 'absolute', left: (c.dx ?? 160) >= 0 ? qx + 18 : undefined, right: (c.dx ?? 160) < 0 ? 1920 - qx + 18 : undefined, top: qy - 26, fontFamily: DISPLAY, fontSize: 40, fontWeight: 300, color: tone.fg, whiteSpace: 'nowrap', opacity: ramp(frame, c.at + 10, c.at + 24)}}>{c.text}</div>
          </React.Fragment>
        );
      })}
    </AbsoluteFill>
  );
};

/** A cut-out region of a screenshot, shown as a floating card. */
export const Crop: React.FC<{src: string; rect: Rect; scale?: number; imageWidth?: number; style?: React.CSSProperties}> = ({src, rect, scale = 1.4, imageWidth = 820, style}) => (
  <div style={{width: rect.w * scale, height: rect.h * scale, borderRadius: 14, overflow: 'hidden', position: 'relative', boxShadow: '0 30px 70px rgba(0,0,0,0.4), 0 0 0 1px rgba(255,255,255,0.06)', background: APP.win, ...style}}>
    <Img src={staticFile(src)} style={{position: 'absolute', left: -rect.x * scale, top: -rect.y * scale, width: imageWidth * scale}} />
  </div>
);

/** Voice-like bar levels, smoothed random, louder while `speaking` is 1. */
const levels = (frame: number, speaking: number, count = 9) =>
  Array.from({length: count}, (_, i) => {
    const k = Math.floor(frame / 3);
    const f = (frame % 3) / 3;
    const v = mix(random(`bar-${i}-${k}`), random(`bar-${i}-${k + 1}`), f);
    const shape = 1 - Math.abs(i - (count - 1) / 2) / count;
    return speaking * Math.min(1, v * 0.9 + 0.1) * (0.55 + 0.45 * shape);
  });

/** Sotto's pill, from the UI design: red dot, bars and timer, live text above. */
export const Pill: React.FC<{show: number; speaking: number; text?: string; seconds: number; scale?: number}> = ({show, speaking, text, seconds, scale = 1}) => {
  const frame = useCurrentFrame();
  if (show <= 0.001) return null;
  return (
    <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, fontFamily: UI, opacity: show, transform: `scale(${scale * mix(0.92, 1, show)}) translateY(${mix(10, 0, show)}px)`, transformOrigin: 'bottom center'}}>
      {text ? <div style={{maxWidth: 520, padding: '10px 14px', borderRadius: 14, background: APP.glass, border: `1px solid ${APP.glassRing}`, boxShadow: '0 12px 32px rgba(0,0,0,0.4)', fontSize: 14, lineHeight: 1.4, color: APP.fg}}>{text}</div> : null}
      <div style={{display: 'flex', alignItems: 'center', gap: 12, height: 48, padding: '0 18px 0 16px', borderRadius: 24, background: APP.glass, border: `1px solid ${APP.glassRing}`, boxShadow: '0 12px 32px rgba(0,0,0,0.4), inset 0 1px 0 rgba(255,255,255,0.12)'}}>
        <span style={{width: 8, height: 8, borderRadius: 4, background: APP.rec, opacity: 0.75 + 0.25 * Math.sin(frame / 5)}} />
        <div style={{display: 'flex', alignItems: 'center', gap: 3, height: 28}}>
          {levels(frame, speaking).map((level, i) => (
            <span key={i} style={{width: 3, height: 6 + 22 * level, borderRadius: 2, background: APP.fg}} />
          ))}
        </div>
        <span style={{fontSize: 13, fontWeight: 500, color: '#D1D1D6', fontVariantNumeric: 'tabular-nums'}}>0:{String(Math.floor(seconds)).padStart(2, '0')}</span>
      </div>
    </div>
  );
};

/** A dark macOS window, as the app's own windows look in dark mode. */
export const AppWindow: React.FC<{title: string; width: number; height: number; children?: React.ReactNode}> = ({title, width, height, children}) => (
  <div style={{width, height, borderRadius: 14, background: APP.win, boxShadow: '0 40px 90px rgba(0,0,0,0.45), 0 0 0 1px rgba(0,0,0,0.5), inset 0 0 0 1px rgba(255,255,255,0.06)', overflow: 'hidden', position: 'relative', fontFamily: UI, color: APP.fg}}>
    <div style={{height: 44, display: 'flex', alignItems: 'center', gap: 8, padding: '0 16px', borderBottom: `1px solid ${APP.sep}`}}>
      {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
        <span key={c} style={{width: 12, height: 12, borderRadius: 6, background: c}} />
      ))}
      <span style={{marginLeft: 14, fontSize: 13, fontWeight: 600, color: APP.fg2}}>{title}</span>
    </div>
    <div style={{position: 'absolute', top: 44, left: 0, right: 0, bottom: 0}}>{children}</div>
  </div>
);

export const Caret: React.FC<{height?: number; color?: string}> = ({height = 20, color = APP.accent}) => {
  const frame = useCurrentFrame();
  return <span style={{display: 'inline-block', width: 2, height, marginLeft: 2, verticalAlign: '-0.15em', background: color, opacity: Math.floor(frame / 15) % 2 === 0 ? 1 : 0}} />;
};

/** A physical key, drawn plainly. `down` 0 → 1 presses it. */
export const Key: React.FC<{glyph: string; label: string; down: number; size?: number}> = ({glyph, label, down, size = 150}) => {
  const accent = useAccent();
  return (
  <div style={{position: 'relative', width: size, height: size + 12}}>
    <div style={{position: 'absolute', left: 0, right: 0, top: 12, height: size, borderRadius: size * 0.18, background: '#05090D'}} />
    <div style={{position: 'absolute', left: 0, right: 0, top: mix(0, 9, down), height: size, borderRadius: size * 0.18, background: 'linear-gradient(#26303A, #1A222B)', boxShadow: `inset 0 1px 0 rgba(255,255,255,0.08), 0 0 0 ${down > 0.5 ? 2 : 0}px ${accent}`, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', justifyContent: 'space-between', padding: size * 0.12, boxSizing: 'border-box', fontFamily: UI, color: '#E8EDF1'}}>
      <span style={{fontSize: size * 0.3, lineHeight: 1}}>{glyph}</span>
      <span style={{fontSize: size * 0.12, color: '#9AA6B2'}}>{label}</span>
    </div>
  </div>
  );
};

/** The Sotto squiggle from the menu bar icon, drawn on by `t`. */
export const Mark: React.FC<{t: number; size?: number; color: string; stroke?: number}> = ({t, size = 120, color, stroke = 1.2}) => (
  <svg width={size * 1.5} height={size} viewBox="0 0 18 12" style={{overflow: 'visible'}}>
    <path d="M1 6c1.6 0 1.9-4 3.6-4S6.9 10 8.6 10 11 2 12.7 2 15.3 6 17 6" fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - t} />
  </svg>
);

/** A red-pencil strike: a slightly uneven stroke drawn left to right. */
export const Strike: React.FC<{t: number; width: number; seed: string}> = ({t, width, seed}) => {
  const accent = useAccent();
  const wobble = (n: number) => (random(`${seed}-${n}`) - 0.5) * 6;
  const d = `M -6 ${wobble(1)} C ${width * 0.3} ${wobble(2)}, ${width * 0.6} ${wobble(3)}, ${width + 6} ${wobble(4)}`;
  return (
    <svg width={width + 12} height={20} viewBox={`-6 -10 ${width + 12} 20`} style={{position: 'absolute', left: -6, top: '52%', marginTop: -10, overflow: 'visible'}}>
      <path d={d} fill="none" stroke={accent} strokeWidth={7} strokeLinecap="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - t} opacity={0.9} />
    </svg>
  );
};

/** One sound effect from public/sfx, at a scene-relative frame. */
export const Sfx: React.FC<{at: number; name: string; volume?: number}> = ({at, name, volume = 0.5}) => (
  <Sequence from={Math.max(0, Math.round(at))} durationInFrames={FPS * 3} layout="none">
    <Audio src={staticFile(`sfx/${name}.wav`)} volume={volume} />
  </Sequence>
);
