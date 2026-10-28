import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {DISPLAY, MARGIN, MONO, type Tone} from '../theme';
import {ramp} from '../motion';
import {said, type Voice} from '../timeline';
import {Line, Mark, Note, Sfx, Staff} from '../kit';

type Props = {tone: Tone; frames: number; voice: Voice};

export const End: React.FC<Props> = ({tone, voice}) => {
  const frame = useCurrentFrame();
  const name = said(voice, 'sotto');
  return (
    <AbsoluteFill>
      <Staff t={ramp(frame, 0, 46)} y={800} color={tone.faint} />
      <div style={{position: 'absolute', left: MARGIN, top: 230}}>
        <Mark t={ramp(frame, name - 24, name + 16)} size={70} color={tone.accent} stroke={1.3} />
      </div>
      <div style={{position: 'absolute', left: MARGIN - 8, top: 320, fontFamily: DISPLAY, fontWeight: 400, fontSize: 240, lineHeight: 1, letterSpacing: '-0.05em', color: tone.fg}}>
        <Line at={name - 4} dur={28}>Sotto</Line>
      </div>
      <div style={{position: 'absolute', left: MARGIN, top: 590, fontFamily: DISPLAY, fontWeight: 300, fontSize: 60, letterSpacing: '-0.02em', color: tone.fg}}>
        <Line at={name + 14}>Offline dictation for the Mac.</Line>
      </div>
      <div style={{position: 'absolute', left: MARGIN, top: 680, fontFamily: DISPLAY, fontWeight: 300, fontSize: 60, letterSpacing: '-0.02em', color: tone.accent}}>
        <Line at={said(voice, 'windows') - 4}>Windows and Linux, soon.</Line>
      </div>
      <Note tone={tone} at={said(voice, 'free') - 4} style={{position: 'absolute', left: MARGIN, top: 880, fontSize: 24}}>
        free and open source · <span style={{color: tone.fg, fontFamily: MONO}}>github.com/FurkanCodes/Sotto</span>
      </Note>
      <Sfx at={name - 24} name="chime" volume={0.45} />
    </AbsoluteFill>
  );
};
