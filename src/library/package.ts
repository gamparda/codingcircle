import JSZip from 'jszip';
import { parseChart } from '../core/chart';
import type { ChartFile } from '../core/types';
import type { SongPackage } from './storage';

export interface ImportedSongPackage {
  chart: ChartFile;
  audioBlob?: Blob;
  audioFileName?: string | null;
}

const chartPath = 'chart.json';
const metadataPath = 'metadata.json';
const audioPrefix = 'audio/';

function safeFileName(name: string): string {
  return name.replace(/[\\/:*?"<>|]+/g, '-').replace(/^\.+$/, 'audio').trim() || 'audio';
}

export async function exportSongPackage(song: SongPackage): Promise<Blob> {
  const zip = new JSZip();
  zip.file(chartPath, JSON.stringify(song.chart, null, 2));
  zip.file(metadataPath, JSON.stringify({ title: song.title, audioFileName: song.audioFileName ?? null, format: 'sidebeat-lanes-package-v1' }, null, 2));
  if (song.audioBlob && song.audioFileName) zip.file(`${audioPrefix}${safeFileName(song.audioFileName)}`, await song.audioBlob.arrayBuffer());
  return zip.generateAsync({ type: 'blob', compression: 'DEFLATE' });
}

export async function importSongPackage(file: Blob): Promise<ImportedSongPackage> {
  const zip = await JSZip.loadAsync(await file.arrayBuffer());
  const chartEntry = zip.file(chartPath) ?? zip.file(/(^|\/)chart\.json$/i)[0];
  if (!chartEntry) throw new Error('chart.json을 찾을 수 없습니다.');

  const chart = parseChart(await chartEntry.async('text'));
  const audioEntry = zip.file(/^audio\//i).find((entry) => !entry.dir);
  if (!audioEntry) return { chart, audioFileName: chart.audioFileName ?? null };

  const audioBlob = new Blob([await audioEntry.async('arraybuffer')]);
  const audioFileName = audioEntry.name.split('/').pop() || chart.audioFileName || 'audio';
  return { chart: { ...chart, audioFileName }, audioBlob, audioFileName };
}

export function packageFileName(title: string): string {
  return `${safeFileName(title).replace(/\s+/g, '-')}.sidebeat.zip`;
}
