import { describe, expect, it } from 'vitest';
import { buildChartFile, normalizeNotes, parseChart } from './chart';

describe('chart core', () => {
  it('normalizes notes by lane/time and strips invalid notes', () => {
    expect(normalizeNotes([
      { lane: 2, time: 300, duration: 100 },
      { lane: 1, time: 100 },
      { lane: 7, time: 50 },
      { lane: 0, time: -1 },
      { lane: 0, time: Number.NaN },
    ]).map(({ lane, time, duration }) => ({ lane, time, duration }))).toEqual([
      { lane: 1, time: 100, duration: 0 },
      { lane: 2, time: 300, duration: 100 },
    ]);
  });

  it('parses v3 chart metadata and normalizes notes/comments', () => {
    const chart = parseChart(JSON.stringify({
      format: 'sidebeat-lanes-chart-v3',
      title: 'Song',
      difficulty: 'hard',
      bpm: 150,
      offset: 32,
      audioFileName: 'song.mp3',
      comments: [{ time: 300, text: 'check this', createdAt: 1 }],
      notes: [{ lane: 3, time: 400 }, { lane: 0, time: 100 }],
    }));

    expect(chart).toMatchObject({
      format: 'sidebeat-lanes-chart-v3',
      title: 'Song',
      difficulty: 'hard',
      bpm: 150,
      offset: 32,
      audioFileName: 'song.mp3',
    });
    expect(chart.comments).toEqual([{ time: 300, text: 'check this', createdAt: 1 }]);
    expect(chart.analysis?.score).toBeGreaterThan(0);
    expect(chart.notes).toEqual([{ lane: 0, time: 100, duration: 0 }, { lane: 3, time: 400, duration: 0 }]);
  });

  it('falls back to v2-compatible defaults for array payloads', () => {
    const chart = parseChart(JSON.stringify([{ lane: 0, time: 1200 }]));
    expect(chart.format).toBe('sidebeat-lanes-chart-v2');
    expect(chart.title).toBe('Untitled Song');
    expect(chart.notes).toEqual([{ lane: 0, time: 1200, duration: 0 }]);
  });

  it('builds v3 chart files', () => {
    expect(buildChartFile({ title: 'Built', bpm: 0, offset: 12, notes: [{ lane: 1, time: 200 }] })).toMatchObject({
      title: 'Built',
      format: 'sidebeat-lanes-chart-v3',
      difficulty: 'normal',
      bpm: 128,
      offset: 12,
      notes: [{ lane: 1, time: 200, duration: 0 }],
    });
  });

  it('rejects payloads without notes', () => {
    expect(() => parseChart('{"title":"bad"}')).toThrow('notes 배열');
  });
});
