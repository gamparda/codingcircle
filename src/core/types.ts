export type DifficultyId = 'easy' | 'normal' | 'hard' | 'expert';

export interface ChartNote {
  lane: number;
  time: number;
  duration?: number;
}

export interface PlayableNote extends Required<ChartNote> {
  hit: boolean;
  missed: boolean;
  holding: boolean;
  completed: boolean;
}

export interface ChartComment {
  time: number;
  text: string;
  createdAt: number;
}

export interface DifficultyMetrics {
  score: number;
  label: DifficultyId;
  density: number;
  peakDensity: number;
  longNoteRatio: number;
  chordRatio: number;
  jackRatio: number;
}

export interface ChartFile {
  title: string;
  format: 'sidebeat-lanes-chart-v2' | 'sidebeat-lanes-chart-v3';
  difficulty: DifficultyId;
  bpm: number;
  offset: number;
  latencyMs?: number;
  audioFileName?: string | null;
  generator?: string;
  comments?: ChartComment[];
  analysis?: DifficultyMetrics;
  notes: ChartNote[];
}

export interface DifficultyConfig {
  label: string;
  bpm: number;
  bars: number;
  speed: number;
  missDamage: number;
  emptyDamage: number;
  patterns: Array<number | number[]>;
}

export interface JudgementWindow {
  name: 'Perfect' | 'Great' | 'Good';
  ms: number;
  score: number;
  life: number;
  color: string;
}
