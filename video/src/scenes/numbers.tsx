import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import trace from '../../public/data/cpu-trace.json';
import {DISPLAY, MARGIN, MARKING, MONO, type Tone} from '../theme';
import {said, type Voice} from '../timeline';
import {ramp} from '../motion';
import {Chapter, Em, Headline, Line, Note, Sfx} from '../kit';

type Props = {tone: Tone; frames: number; voice: Voice};

// Cumulative CPU seconds: ps reports CPU time in 10 ms steps, too coarse for
// a per-sample percentage while listening.
const points = trace.points as [number, number][];
const T_MAX = points[points.length - 1][0];
const CHART = {x: 860, y: 300, w: 900, h: 440};
const Y_MAX = 0.4;
const px = (t: number) => CHART.x + (t / T_MAX) * CHART.w;
const py = (s: number) => CHART.y + CHART.h - (s / Y_MAX) * CHART.h;
const RELEASE_T = 15.2;
const listening = points.filter(([t]) => t <= RELEASE_T);
const burst = points.filter(([t]) => t >= listening[listening.length - 1][0]);
const PATH = (pts: [number, number][]) => pts.map(([t, s], i) => `${i ? 'L' : 'M'}${px(t).toFixed(1)},${py(s).toFixed(1)}`).join(' ');

export const Quiet: React.FC<Props> = ({tone}) => {
  const frame = useCurrentFrame();
  const draw = ramp(frame, 70, 160);
  const step = ramp(frame, 160, 176);
  const axes = ramp(frame, 50, 80);
  return (
    <AbsoluteFill>
      <Chapter n={8} title="Quiet" tone={tone} />
      <div style={{position: 'absolute', left: MARGIN - 8, top: 170, fontFamily: MARKING, fontWeight: 400, fontSize: 230, lineHeight: 1, color: tone.accent}}>
        <Line at={10} dur={26}>pp</Line>
      </div>
      <Headline at={30} tone={tone} size={80} lines={["When you're quiet,", <>Sotto <Em color={tone.fg}>is too.</Em></>]} style={{position: 'absolute', left: MARGIN, top: 470}} />
      <Note tone={tone} at={44} style={{position: 'absolute', left: MARGIN, top: 690, width: 640}}>
        idle: 0.00% CPU · 0 wake-ups/s · 33 MB
        <br />
        the mic is open only while you hold the key
      </Note>

      <svg width={1920} height={1080} style={{position: 'absolute', inset: 0, overflow: 'visible'}}>
        <g opacity={axes}>
          <line x1={CHART.x} x2={CHART.x + CHART.w} y1={py(0)} y2={py(0)} stroke={tone.dim} strokeWidth={1} />
          {[0.1, 0.2, 0.3].map((v) => (
            <g key={v}>
              <line x1={CHART.x} x2={CHART.x + CHART.w} y1={py(v)} y2={py(v)} stroke={tone.faint} strokeWidth={1} strokeDasharray="2 6" />
              <text x={CHART.x + CHART.w + 14} y={py(v) + 7} fontFamily={MONO} fontSize={18} fill={tone.dim}>{v.toFixed(1)} s</text>
            </g>
          ))}
          <text x={CHART.x} y={py(0) + 40} fontFamily={MONO} fontSize={18} fill={tone.dim}>0 s</text>
          <text x={CHART.x + CHART.w} y={py(0) + 40} fontFamily={MONO} fontSize={18} fill={tone.dim} textAnchor="end">{trace.audio_seconds} s of talking</text>
        </g>
        <path d={PATH(listening)} fill="none" stroke={tone.fg} strokeWidth={2.5} strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - draw} />
        <path d={PATH(burst)} fill="none" stroke={tone.accent} strokeWidth={3} strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - step} />
      </svg>
      <div style={{position: 'absolute', left: px(1.5), top: py(0.1) - 74, fontFamily: MONO, fontSize: 20, color: tone.dim, opacity: ramp(frame, 110, 130)}}>listening: {trace.listening_cpu_seconds.toFixed(2)} s of CPU in 15 s</div>
      <div style={{position: 'absolute', right: 1920 - px(T_MAX) + 30, top: py(trace.cpu_seconds_dictation) - 20, textAlign: 'right', opacity: ramp(frame, 176, 196)}}>
        <div style={{fontFamily: DISPLAY, fontWeight: 300, fontSize: 84, letterSpacing: '-0.03em', color: tone.fg, lineHeight: 1}}>{trace.cpu_seconds_dictation.toFixed(2)} s</div>
        <div style={{fontFamily: MONO, fontSize: 20, color: tone.dim, marginTop: 10}}>of CPU, the whole dictation</div>
      </div>
      <Note tone={tone} at={190} style={{position: 'absolute', left: CHART.x, top: 860, width: 900, fontSize: 18}}>
        signed app, a 15.4 s recording fed in real time; CPU time from ps every 100 ms. Apple M5.
      </Note>
      <Sfx at={70} name="rise" volume={0.14} />
      <Sfx at={162} name="pop" volume={0.22} />
    </AbsoluteFill>
  );
};

// docs/measurements.md, "Power, Neural Engine against GPU".
const NEURAL = 0.461;
const GPU = 2.692;

export const Battery: React.FC<Props> = ({tone, voice}) => {
  const frame = useCurrentFrame();
  const neuralAt = said(voice, 'neural');
  const gpuAt = said(voice, 'gpu');
  const bars = [
    {label: 'Neural Engine', watts: NEURAL, t: ramp(frame, neuralAt, neuralAt + 30), color: tone.fg},
    {label: 'GPU', watts: GPU, t: ramp(frame, gpuAt - 6, gpuAt + 40), color: tone.dim},
  ];
  return (
    <AbsoluteFill>
      <Chapter n={9} title="Battery" tone={tone} />
      <Headline at={8} tone={tone} size={124} lines={[<><Em>{(GPU / NEURAL).toFixed(1)}×</Em> less power</>, 'on the Neural Engine.']} style={{position: 'absolute', left: MARGIN, top: 230}} />
      <div style={{position: 'absolute', left: MARGIN, top: 560, width: 1620, display: 'flex', flexDirection: 'column', gap: 50}}>
        {bars.map((bar) => (
          <div key={bar.label} style={{display: 'flex', alignItems: 'center', gap: 40, opacity: Math.min(1, bar.t * 3)}}>
            <span style={{width: 260, fontFamily: MONO, fontSize: 20, letterSpacing: '0.14em', textTransform: 'uppercase', color: tone.dim}}>{bar.label}</span>
            <div style={{flex: 1, height: 3, background: tone.faint, position: 'relative'}}>
              <div style={{position: 'absolute', left: 0, top: -7, height: 17, width: `${(bar.watts / GPU) * 100 * bar.t}%`, background: bar.color}} />
            </div>
            <span style={{width: 280, whiteSpace: 'nowrap', textAlign: 'right', fontFamily: DISPLAY, fontWeight: 300, fontSize: 72, letterSpacing: '-0.02em', color: tone.fg, fontVariantNumeric: 'tabular-nums'}}>{(bar.watts * bar.t).toFixed(2)} W</span>
          </div>
        ))}
      </div>
      <Note tone={tone} at={120} style={{position: 'absolute', left: MARGIN, top: 900, width: 1300, fontSize: 18}}>
        whole-system power from powermetrics, streaming the same 45.8 s recording through Parakeet Unified on each, with the same text from both. Apple M5.
      </Note>
      <Sfx at={neuralAt} name="rise" volume={0.2} />
      <Sfx at={gpuAt - 6} name="rise" volume={0.25} />
    </AbsoluteFill>
  );
};

