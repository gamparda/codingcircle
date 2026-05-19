import { beforeEach, describe, expect, it, vi } from 'vitest';
import { IDBFactory } from 'fake-indexeddb';
import { buildChartFile } from '../core/chart';
import { deleteSong, getLibrary, getSong, saveSongPackage } from './storage';

function installStorage(): void {
  const data = new Map<string, string>();
  vi.stubGlobal('indexedDB', new IDBFactory());
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => { data.set(key, value); },
    removeItem: (key: string) => { data.delete(key); },
    clear: () => { data.clear(); },
  });
}

beforeEach(() => {
  vi.unstubAllGlobals();
  installStorage();
});

describe('IndexedDB song library', () => {
  it('saves chart and audio blob as one package', async () => {
    const chart = buildChartFile({ title: 'Stored Song', audioFileName: 'stored.mp3', notes: [{ lane: 0, time: 100 }] });
    const audioBlob = new Blob(['audio'], { type: 'audio/mpeg' });

    const saved = await saveSongPackage({ chart, audioBlob, audioFileName: 'stored.mp3' });
    const loaded = await getSong(saved.id);

    expect(loaded?.chart.title).toBe('Stored Song');
    expect(loaded?.audioFileName).toBe('stored.mp3');
    expect(await loaded?.audioBlob?.text()).toBe('audio');
  });

  it('summarizes and deletes songs', async () => {
    const chart = buildChartFile({ title: 'Delete Me', notes: [{ lane: 1, time: 200 }] });
    const saved = await saveSongPackage({ chart });

    expect(await getLibrary()).toEqual([expect.objectContaining({ id: saved.id, title: 'Delete Me', noteCount: 1 })]);
    expect((await deleteSong(saved.id))?.title).toBe('Delete Me');
    expect(await getLibrary()).toEqual([]);
  });

  it('migrates legacy localStorage charts', async () => {
    const legacy = buildChartFile({ title: 'Legacy Song', notes: [{ lane: 2, time: 300 }] });
    localStorage.setItem('sidebeat-lanes-song-library-v2', JSON.stringify([legacy]));

    const library = await getLibrary();

    expect(library).toEqual([expect.objectContaining({ title: 'Legacy Song', noteCount: 1 })]);
  });
});
