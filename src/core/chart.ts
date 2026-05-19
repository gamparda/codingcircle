import { analyzeDifficulty } from './difficulty';
import type { ChartComment, ChartFile, ChartNote, DifficultyConfig, DifficultyId, PlayableNote } from './types';

export const LANES = ['D', 'F', 'J', 'K'] as const;
export const LANE_KEYS = new Map(LANES.map((key, lane) => [key.toLowerCase(), lane]));
export const chartOffsetMs = 1200;

export const difficulties: Record<DifficultyId, DifficultyConfig> = {
  easy: { label: 'Easy', bpm: 104, bars: 6, speed: .86, missDamage: 6, emptyDamage: 2, patterns: [0, 1, 2, 3, 0, 1, 2, 3] },
  normal: { label: 'Normal', bpm: 128, bars: 8, speed: 1, missDamage: 8, emptyDamage: 3, patterns: [0, 1, 2, 3, 1, 0, 3, 2, [0, 2], 1, 3, [1, 3], 2, 0, 1, 3] },
  hard: { label: 'Hard', bpm: 150, bars: 10, speed: 1.18, missDamage: 10, emptyDamage: 4, patterns: [0, 2, 1, 3, [0, 1], 2, 3, 1, [2, 3], 0, 1, [0, 3], 2, 1, 3, [1, 2]] },
  expert: { label: 'Expert', bpm: 172, bars: 12, speed: 1.34, missDamage: 12, emptyDamage: 5, patterns: [0, [1, 3], 2, 1, [0, 2], 3, 0, [1, 2], 3, 2, [0, 3], 1, 0, 2, [1, 3], [0, 2]] },
};

export function makeDemoChart(difficultyId: DifficultyId): ChartNote[] {
  const difficulty = difficulties[difficultyId];
  const notes: ChartNote[] = [];
  const beat = 60000 / difficulty.bpm;
  for (let bar = 0; bar < difficulty.bars; bar += 1) {
    difficulty.patterns.forEach((pattern, index) => {
      const time = chartOffsetMs + (bar * difficulty.patterns.length + index) * (beat / 2);
      const lanes = Array.isArray(pattern) ? pattern : [pattern];
      lanes.forEach((lane) => notes.push({ lane, time, duration: index % 15 === 8 ? beat : 0 }));
    });
  }
  return normalizeNotes(notes);
}

export function normalizeNotes(notes: ChartNote[]): PlayableNote[] {
  return notes
    .map((note) => ({ lane: Number(note.lane), time: Number(note.time), duration: Math.max(0, Number(note.duration) || 0), hit: false, missed: false, holding: false, completed: false }))
    .filter((note) => Number.isFinite(note.time) && note.time >= 0 && note.lane >= 0 && note.lane < LANES.length)
    .sort((a, b) => a.time - b.time || a.lane - b.lane);
}

function normalizeComments(comments: unknown): ChartComment[] {
  if (!Array.isArray(comments)) return [];
  return comments
    .map((comment) => comment as Partial<ChartComment>)
    .filter((comment) => Number.isFinite(Number(comment.time)) && String(comment.text || '').trim())
    .map((comment) => ({ time: Math.max(0, Math.round(Number(comment.time))), text: String(comment.text).trim(), createdAt: Number(comment.createdAt) || Date.now() }))
    .sort((a, b) => a.time - b.time || a.createdAt - b.createdAt);
}

export function parseChart(text: string): ChartFile {
  const payload = JSON.parse(text) as Partial<ChartFile> | ChartNote[];
  const source = Array.isArray(payload) ? { notes: payload } : payload;
  if (!Array.isArray(source.notes)) throw new Error('notes 배열을 찾을 수 없습니다.');
  const chart = {
    title: source.title || 'Untitled Song',
    format: source.format === 'sidebeat-lanes-chart-v3' ? 'sidebeat-lanes-chart-v3' as const : 'sidebeat-lanes-chart-v2' as const,
    difficulty: source.difficulty && source.difficulty in difficulties ? source.difficulty : 'normal',
    bpm: Number(source.bpm) || difficulties.normal.bpm,
    offset: Number(source.offset) || 0,
    latencyMs: Number(source.latencyMs) || 0,
    audioFileName: source.audioFileName ?? null,
    generator: source.generator,
    comments: normalizeComments(source.comments),
    notes: normalizeNotes(source.notes).map(({ lane, time, duration }) => ({ lane, time, duration })),
  };
  return { ...chart, analysis: analyzeDifficulty(chart) };
}

export function buildChartFile(input: Partial<ChartFile> & { notes: ChartNote[] }): ChartFile {
  const chart = {
    title: input.title || 'Untitled Song',
    format: 'sidebeat-lanes-chart-v3' as const,
    difficulty: input.difficulty || 'normal',
    bpm: Number(input.bpm) || difficulties.normal.bpm,
    offset: Number(input.offset) || 0,
    latencyMs: Number(input.latencyMs) || 0,
    audioFileName: input.audioFileName ?? null,
    generator: input.generator,
    comments: normalizeComments(input.comments),
    notes: normalizeNotes(input.notes).map(({ lane, time, duration }) => ({ lane, time, duration })),
  };
  return { ...chart, analysis: analyzeDifficulty(chart) };
}
