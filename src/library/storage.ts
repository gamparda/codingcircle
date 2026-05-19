import type { ChartFile } from '../core/types';

const dbName = 'sidebeat-lanes-library';
const dbVersion = 1;
const songStore = 'songs';
const legacyChartStoreKey = 'sidebeat-lanes-song-library-v2';
const migrationKey = 'sidebeat-lanes-idb-migrated-v1';

export interface SongPackage {
  id: string;
  title: string;
  chart: ChartFile;
  audioBlob?: Blob;
  audioFileName?: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface SongSummary {
  id: string;
  title: string;
  noteCount: number;
  audioFileName?: string | null;
  updatedAt: number;
}

function makeId(title: string): string {
  const slug = title.toLowerCase().replace(/[^a-z0-9가-힣]+/gi, '-').replace(/^-|-$/g, '') || 'song';
  return `${slug}-${Date.now().toString(36)}`;
}

function openLibrary(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName, dbVersion);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(songStore)) {
        const store = db.createObjectStore(songStore, { keyPath: 'id' });
        store.createIndex('title', 'title', { unique: false });
        store.createIndex('updatedAt', 'updatedAt', { unique: false });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('IndexedDB를 열 수 없습니다.'));
  });
}

async function withStore<T>(mode: IDBTransactionMode, run: (store: IDBObjectStore) => IDBRequest<T> | void): Promise<T | undefined> {
  const db = await openLibrary();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(songStore, mode);
    const store = transaction.objectStore(songStore);
    const request = run(store);
    let value: T | undefined;
    if (request) {
      request.onsuccess = () => { value = request.result; };
      request.onerror = () => reject(request.error ?? new Error('IndexedDB 작업에 실패했습니다.'));
    }
    transaction.oncomplete = () => { db.close(); resolve(value); };
    transaction.onerror = () => { db.close(); reject(transaction.error ?? new Error('IndexedDB 트랜잭션에 실패했습니다.')); };
  });
}

export async function migrateLegacyLibrary(): Promise<void> {
  if (localStorage.getItem(migrationKey)) return;
  let legacy: ChartFile[] = [];
  try { legacy = JSON.parse(localStorage.getItem(legacyChartStoreKey) || '[]') as ChartFile[]; }
  catch { legacy = []; }
  for (const chart of legacy) await saveSongPackage({ chart });
  localStorage.setItem(migrationKey, '1');
}

export async function getLibrary(): Promise<SongSummary[]> {
  await migrateLegacyLibrary();
  const songs = (await withStore<SongPackage[]>('readonly', (store) => store.getAll())) ?? [];
  return songs
    .map((song) => ({ id: song.id, title: song.title, noteCount: song.chart.notes.length, audioFileName: song.audioFileName ?? song.chart.audioFileName ?? null, updatedAt: song.updatedAt }))
    .sort((a, b) => b.updatedAt - a.updatedAt || a.title.localeCompare(b.title));
}

export async function getSong(id: string): Promise<SongPackage | undefined> {
  await migrateLegacyLibrary();
  return withStore<SongPackage>('readonly', (store) => store.get(id));
}

export async function saveSongPackage(input: { chart: ChartFile; audioBlob?: Blob; audioFileName?: string | null; id?: string }): Promise<SongPackage> {
  const now = Date.now();
  const library = (await withStore<SongPackage[]>('readonly', (store) => store.getAll())) ?? [];
  const existing = input.id ? library.find((song) => song.id === input.id) : library.find((song) => song.title === input.chart.title);
  const audioBlob = input.audioBlob ?? existing?.audioBlob;
  const audioFileName = input.audioFileName ?? input.chart.audioFileName ?? existing?.audioFileName ?? null;
  const chart = { ...input.chart, audioFileName };
  const song: SongPackage = {
    id: existing?.id ?? input.id ?? makeId(chart.title),
    title: chart.title,
    chart,
    audioBlob,
    audioFileName,
    createdAt: existing?.createdAt ?? now,
    updatedAt: now,
  };
  await withStore('readwrite', (store) => { store.put(song); });
  return song;
}

export async function deleteSong(id: string): Promise<SongPackage | undefined> {
  const existing = await getSong(id);
  if (!existing) return undefined;
  await withStore('readwrite', (store) => { store.delete(id); });
  return existing;
}

export async function saveChart(chart: ChartFile): Promise<void> {
  await saveSongPackage({ chart });
}
