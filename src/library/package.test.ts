import { describe, expect, it } from 'vitest';
import { buildChartFile } from '../core/chart';
import { exportSongPackage, importSongPackage, packageFileName } from './package';
import type { SongPackage } from './storage';

describe('song package zip', () => {
  it('exports and imports chart with audio', async () => {
    const chart = buildChartFile({ title: 'Zip Song', audioFileName: 'zip.mp3', notes: [{ lane: 0, time: 100 }] });
    const song: SongPackage = { id: 'zip', title: 'Zip Song', chart, audioBlob: new Blob(['audio']), audioFileName: 'zip.mp3', createdAt: 1, updatedAt: 2 };

    const blob = await exportSongPackage(song);
    const imported = await importSongPackage(blob);

    expect(imported.chart.title).toBe('Zip Song');
    expect(imported.audioFileName).toBe('zip.mp3');
    expect(await imported.audioBlob?.text()).toBe('audio');
  });

  it('makes safe package names', () => {
    expect(packageFileName('A/B Song')).toBe('A-B-Song.sidebeat.zip');
  });
});
