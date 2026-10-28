import {loadFont as loadBricolage} from '@remotion/google-fonts/BricolageGrotesque';
import {loadFont as loadFraunces} from '@remotion/google-fonts/Fraunces';
import {loadFont as loadPlexMono} from '@remotion/google-fonts/IBMPlexMono';

// Night and fog, lit by one sodium-amber accent: a quiet street at night.
// Midnight scenes and fog scenes alternate; the amber is darker on fog so
// it keeps its contrast.
export const onInk = {bg: '#0B1622', fg: '#E8EDF1', dim: '#8193A3', faint: 'rgba(232,237,241,0.14)', accent: '#F5B041'};
export const onPaper = {bg: '#DFE5EA', fg: '#0D1B26', dim: '#56697A', faint: 'rgba(13,27,38,0.14)', accent: '#B5650B'};
export type Tone = typeof onInk;

export const DISPLAY = loadBricolage('normal', {weights: ['300', '400', '500'], subsets: ['latin', 'latin-ext']}).fontFamily;
export const MONO = loadPlexMono('normal', {weights: ['400', '500'], subsets: ['latin', 'latin-ext']}).fontFamily;
// Only for musical markings (sotto voce, pp), which scores set in italic.
export const MARKING = loadFraunces('italic', {weights: ['300', '400'], subsets: ['latin']}).fontFamily;
export const UI = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif";

// The app's dark tokens, from the UI design canvas, for recreated app UI.
export const APP = {
  win: '#1E1E21',
  winRing: 'rgba(255,255,255,0.10)',
  sep: 'rgba(255,255,255,0.08)',
  fg: '#F5F5F7',
  fg2: '#A1A1A6',
  glass: 'rgba(44,44,48,0.92)',
  glassRing: 'rgba(255,255,255,0.14)',
  rec: '#FF453A',
  accent: '#0A84FF',
  hilite: 'rgba(10,132,255,0.30)',
};

export const W = 1920;
export const H = 1080;
export const FPS = 30;
export const MARGIN = 150;
