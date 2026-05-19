import { describe, expect, it } from 'vitest';
import { judgementWindows, rankForAccuracy } from './judgement';

describe('judgement core', () => {
  it('keeps judgement windows ordered from strict to loose', () => {
    expect(judgementWindows.map((window) => window.name)).toEqual(['Perfect', 'Great', 'Good']);
    expect(judgementWindows.map((window) => window.ms)).toEqual([45, 90, 140]);
  });

  it.each([
    [100, 'SS'],
    [98, 'SS'],
    [97.99, 'S'],
    [94, 'S'],
    [88, 'A'],
    [80, 'B'],
    [70, 'C'],
    [69.99, 'D'],
  ])('ranks %s accuracy as %s', (accuracy, rank) => {
    expect(rankForAccuracy(accuracy)).toBe(rank);
  });
});
