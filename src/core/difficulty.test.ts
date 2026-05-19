import { describe, expect, it } from 'vitest';
import { analyzeDifficulty } from './difficulty';

describe('difficulty analysis', () => {
  it('returns easy metrics for empty charts', () => {
    expect(analyzeDifficulty({ bpm: 120, notes: [] })).toMatchObject({ score: 0, label: 'easy' });
  });

  it('scores dense charts higher than sparse charts', () => {
    const sparse = analyzeDifficulty({ bpm: 100, notes: [{ lane: 0, time: 0 }, { lane: 1, time: 5000 }] });
    const dense = analyzeDifficulty({ bpm: 180, notes: Array.from({ length: 40 }, (_, index) => ({ lane: index % 4, time: index * 125 })) });

    expect(dense.score).toBeGreaterThan(sparse.score);
    expect(['hard', 'expert']).toContain(dense.label);
  });

  it('reports long note ratio and peak density', () => {
    const metrics = analyzeDifficulty({ bpm: 128, notes: [{ lane: 0, time: 0, duration: 800 }, { lane: 1, time: 250 }] });
    expect(metrics.longNoteRatio).toBe(.5);
    expect(metrics.peakDensity).toBeGreaterThan(0);
  });
});
