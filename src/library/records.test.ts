import { beforeEach, describe, expect, it, vi } from 'vitest';
import { addPlayRecord, bestRecord, recentRecords } from './records';

beforeEach(() => {
  const data = new Map<string, string>();
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => { data.set(key, value); },
    removeItem: (key: string) => { data.delete(key); },
    clear: () => { data.clear(); },
  });
});

describe('play records', () => {
  it('stores recent records and finds best score per song', () => {
    addPlayRecord({ songTitle: 'Song', difficulty: 'Normal', score: 100, accuracy: 90, maxCombo: 10, notes: 20, rank: 'B' });
    addPlayRecord({ songTitle: 'Song', difficulty: 'Normal', score: 200, accuracy: 88, maxCombo: 12, notes: 20, rank: 'A' });

    expect(recentRecords(1)[0]).toMatchObject({ score: 200 });
    expect(bestRecord('Song')).toMatchObject({ score: 200 });
  });
});
