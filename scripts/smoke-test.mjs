import { readFile } from 'node:fs/promises';

const requiredFiles = [
  'index.html',
  'admin.html',
  'src/main.ts',
  'src/admin.ts',
  'src/admin/Timeline.ts',
  'src/admin/LibraryPanel.ts',
  'src/admin/ChartList.ts',
  'src/admin/CommentList.ts',
  'src/core/types.ts',
  'src/core/chart.ts',
  'src/game/GameApp.ts',
  'src/core/difficulty.ts',
  'src/library/package.ts',
  'src/library/records.ts',
  'tools/chartgen/generate_chart.py',
  'tools/chartgen/server.py',
  'tools/chartgen/requirements.txt',
  'README.md',
];

for (const file of requiredFiles) {
  const contents = await readFile(new URL(`../${file}`, import.meta.url), 'utf8');
  if (!contents.trim()) throw new Error(`${file} is empty`);
}

const mainHtml = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const adminHtml = await readFile(new URL('../admin.html', import.meta.url), 'utf8');
const types = await readFile(new URL('../src/core/types.ts', import.meta.url), 'utf8');
const chart = await readFile(new URL('../src/core/chart.ts', import.meta.url), 'utf8');
const game = await readFile(new URL('../src/game/GameApp.ts', import.meta.url), 'utf8');
const admin = await readFile(new URL('../src/admin.ts', import.meta.url), 'utf8');
const timeline = await readFile(new URL('../src/admin/Timeline.ts', import.meta.url), 'utf8');
const difficulty = await readFile(new URL('../src/core/difficulty.ts', import.meta.url), 'utf8');
const storage = await readFile(new URL('../src/library/storage.ts', import.meta.url), 'utf8');
const records = await readFile(new URL('../src/library/records.ts', import.meta.url), 'utf8');
const packageTs = await readFile(new URL('../src/library/package.ts', import.meta.url), 'utf8');
const py = await readFile(new URL('../tools/chartgen/generate_chart.py', import.meta.url), 'utf8');
const server = await readFile(new URL('../tools/chartgen/server.py', import.meta.url), 'utf8');

for (const token of ['chartUpload', 'audioUpload', 'songLibrary', '/src/main.ts']) {
  if (!mainHtml.includes(token)) throw new Error(`index.html missing ${token}`);
}
for (const token of ['Admin Studio', '/admin.html']) {
  if (mainHtml.includes(token)) throw new Error(`index.html should not expose ${token}`);
}
for (const token of ['AUTO CHARTGEN', 'generatedChartUpload', 'packageUpload', 'generateFromServer', 'commentInput', 'difficultyScore', 'timeline', '/src/admin.ts']) {
  if (!adminHtml.includes(token)) throw new Error(`admin.html missing ${token}`);
}
for (const token of ['interface ChartFile', 'interface ChartNote', 'interface ChartComment', 'DifficultyMetrics', 'sidebeat-lanes-chart-v3']) {
  if (!types.includes(token)) throw new Error(`types.ts missing ${token}`);
}
for (const token of ['parseChart', 'buildChartFile', 'normalizeNotes', 'comments', 'analysis']) {
  if (!chart.includes(token)) throw new Error(`chart.ts missing ${token}`);
}
for (const token of ['class GameApp', 'judge', 'release', 'parseChart', 'setPlayFocus', 'addPlayRecord']) {
  if (!game.includes(token)) throw new Error(`GameApp.ts missing ${token}`);
}
for (const token of ['generatedChartUpload', 'saveSongPackage', 'Timeline', 'LibraryPanel', 'ChartList', 'CommentList', 'generateFromServer']) {
  if (!admin.includes(token)) throw new Error(`admin.ts missing ${token}`);
}
for (const token of ['class Timeline', 'drawBeatGrid', 'pointerdown']) {
  if (!timeline.includes(token)) throw new Error(`Timeline.ts missing ${token}`);
}
for (const token of ['analyzeDifficulty', 'peakDensity', 'longNoteRatio']) {
  if (!difficulty.includes(token)) throw new Error(`difficulty.ts missing ${token}`);
}
for (const token of ['indexedDB.open', 'audioBlob', 'migrateLegacyLibrary']) {
  if (!storage.includes(token)) throw new Error(`storage.ts missing ${token}`);
}
for (const token of ['addPlayRecord', 'bestRecord', 'recentRecords']) {
  if (!records.includes(token)) throw new Error(`records.ts missing ${token}`);
}
for (const token of ['JSZip', 'exportSongPackage', 'importSongPackage']) {
  if (!packageTs.includes(token)) throw new Error(`package.ts missing ${token}`);
}
for (const token of ['librosa', 'beat_track', 'onset_detect', 'sidebeat-lanes-chart-v3']) {
  if (!py.includes(token)) throw new Error(`generate_chart.py missing ${token}`);
}
for (const token of ['FastAPI', '/generate', 'UploadFile']) {
  if (!server.includes(token)) throw new Error(`server.py missing ${token}`);
}

console.log('Smoke test passed: TS modules, admin studio, and Python chartgen are present.');
