import type { ChartFile, ChartNote, DifficultyId, DifficultyMetrics } from './types';

function labelForScore(score: number): DifficultyId {
  if (score >= 8) return 'expert';
  if (score >= 5.8) return 'hard';
  if (score >= 3.2) return 'normal';
  return 'easy';
}

function peakDensity(notes: ChartNote[], windowMs = 5000): number {
  if (!notes.length) return 0;
  let best = 0;
  let right = 0;
  for (let left = 0; left < notes.length; left += 1) {
    while (right < notes.length && notes[right].time - notes[left].time <= windowMs) right += 1;
    best = Math.max(best, right - left);
  }
  return best / (windowMs / 1000);
}

function normalizeForAnalysis(notes: ChartNote[]): Required<ChartNote>[] {
  return notes
    .map((note) => ({ lane: Number(note.lane), time: Number(note.time), duration: Math.max(0, Number(note.duration) || 0) }))
    .filter((note) => Number.isFinite(note.time) && note.time >= 0 && note.lane >= 0 && note.lane < 4)
    .sort((a, b) => a.time - b.time || a.lane - b.lane);
}

export function analyzeDifficulty(input: Pick<ChartFile, 'notes' | 'bpm'> | { notes: ChartNote[]; bpm?: number }): DifficultyMetrics {
  const notes = normalizeForAnalysis(input.notes);
  if (!notes.length) return { score: 0, label: 'easy', density: 0, peakDensity: 0, longNoteRatio: 0, chordRatio: 0, jackRatio: 0 };

  const first = notes[0].time;
  const last = Math.max(...notes.map((note) => note.time + (note.duration || 0)));
  const durationSeconds = Math.max(1, (last - first) / 1000);
  const density = notes.length / durationSeconds;
  const peak = peakDensity(notes);
  const longNoteRatio = notes.filter((note) => (note.duration || 0) > 0).length / notes.length;
  const chordRatio = notes.filter((note, index) => index > 0 && Math.abs(note.time - notes[index - 1].time) <= 24).length / notes.length;
  const jackRatio = notes.filter((note, index) => index > 0 && note.lane === notes[index - 1].lane && note.time - notes[index - 1].time <= 220).length / notes.length;
  const bpmFactor = Math.max(0, ((input.bpm || 128) - 120) / 80);
  const score = Math.min(10, Math.max(0, density * 1.05 + peak * .42 + longNoteRatio * 1.15 + chordRatio * 1.75 + jackRatio * 1.35 + bpmFactor));

  return {
    score: Number(score.toFixed(2)),
    label: labelForScore(score),
    density: Number(density.toFixed(2)),
    peakDensity: Number(peak.toFixed(2)),
    longNoteRatio: Number(longNoteRatio.toFixed(3)),
    chordRatio: Number(chordRatio.toFixed(3)),
    jackRatio: Number(jackRatio.toFixed(3)),
  };
}
