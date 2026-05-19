export interface PlayRecord {
  id: string;
  songTitle: string;
  difficulty: string;
  score: number;
  accuracy: number;
  maxCombo: number;
  notes: number;
  rank: string;
  playedAt: number;
}

const key = 'sidebeat-lanes-play-records-v1';
const maxRecords = 200;

export function getPlayRecords(): PlayRecord[] {
  try { return JSON.parse(localStorage.getItem(key) || '[]') as PlayRecord[]; }
  catch { return []; }
}

export function addPlayRecord(record: Omit<PlayRecord, 'id' | 'playedAt'>): PlayRecord {
  const entry: PlayRecord = { ...record, id: `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`, playedAt: Date.now() };
  const records = [entry, ...getPlayRecords()].slice(0, maxRecords);
  localStorage.setItem(key, JSON.stringify(records));
  return entry;
}

export function bestRecord(songTitle: string): PlayRecord | undefined {
  return getPlayRecords()
    .filter((record) => record.songTitle === songTitle)
    .sort((a, b) => b.score - a.score || b.accuracy - a.accuracy || b.maxCombo - a.maxCombo)[0];
}

export function recentRecords(limit = 10): PlayRecord[] {
  return getPlayRecords().slice(0, limit);
}
