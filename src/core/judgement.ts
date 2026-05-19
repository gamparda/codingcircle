import type { JudgementWindow } from './types';

export const judgementWindows: JudgementWindow[] = [
  { name: 'Perfect', ms: 45, score: 1000, life: 2, color: '#72f6d1' },
  { name: 'Great', ms: 90, score: 700, life: 1, color: '#8bb8ff' },
  { name: 'Good', ms: 140, score: 350, life: 0, color: '#ffd166' },
];

export function rankForAccuracy(accuracy: number): string {
  if (accuracy >= 98) return 'SS';
  if (accuracy >= 94) return 'S';
  if (accuracy >= 88) return 'A';
  if (accuracy >= 80) return 'B';
  if (accuracy >= 70) return 'C';
  return 'D';
}
