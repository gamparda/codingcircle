import { difficulties, LANE_KEYS, LANES, makeDemoChart, normalizeNotes, parseChart } from '../core/chart';
import { judgementWindows, rankForAccuracy } from '../core/judgement';
import type { ChartFile, DifficultyId, PlayableNote } from '../core/types';
import { addPlayRecord, bestRecord } from '../library/records';
import { getLibrary, getSong } from '../library/storage';
import { must } from '../ui/dom';

interface GameState { notes: PlayableNote[]; running: boolean; startedAt: number; pausedAt: number; pauseAccumulated: number; score: number; combo: number; maxCombo: number; judged: number; totalHitValue: number; life: number; laneFlash: number[]; nextTick: number; finished: boolean; }

export class GameApp {
  private canvas = must<HTMLCanvasElement>('#game');
  private ctx = this.canvas.getContext('2d')!;
  private audio = must<HTMLAudioElement>('#audioPlayer');
  private difficultySelect = must<HTMLSelectElement>('#difficultySelect');
  private chartUpload = must<HTMLInputElement>('#chartUpload');
  private audioUpload = must<HTMLInputElement>('#audioUpload');
  private songLibrary = must<HTMLSelectElement>('#songLibrary');
  private currentDifficulty: DifficultyId = 'normal';
  private chart: ChartFile | null = null;
  private state!: GameState;
  private animationId = 0;
  private lastFrame = 0;
  private audioContext?: AudioContext;
  private masterGain?: GainNode;
  private held = new Set<number>();
  private effects: Array<{ lane: number; label: string; color: string; age: number }> = [];
  private latencyMs = Number(localStorage.getItem('sidebeat-latency-ms') || 0);
  private audioObjectUrl: string | null = null;

  start(): void {
    must<HTMLButtonElement>('#startButton').addEventListener('click', () => this.toggleStart());
    must<HTMLButtonElement>('#restartButton').addEventListener('click', () => this.reset());
    must<HTMLButtonElement>('#closeResult').addEventListener('click', () => must<HTMLDialogElement>('#resultDialog').close());
    this.difficultySelect.addEventListener('change', () => { this.currentDifficulty = this.difficultySelect.value as DifficultyId; this.chart = null; this.reset(); });
    this.chartUpload.addEventListener('change', () => this.loadChartFile());
    this.audioUpload.addEventListener('change', () => this.loadAudioFile());
    this.songLibrary.addEventListener('change', () => this.loadLibrarySong());
    window.addEventListener('keydown', (event) => this.onKeyDown(event));
    window.addEventListener('keyup', (event) => this.onKeyUp(event));
    void this.renderLibrary();
    this.reset();
  }

  private reset(): void {
    this.setPlayFocus(false);
    cancelAnimationFrame(this.animationId);
    this.audio.pause(); this.audio.currentTime = 0;
    this.state = { notes: this.chart ? normalizeNotes(this.chart.notes) : normalizeNotes(makeDemoChart(this.currentDifficulty)), running: false, startedAt: 0, pausedAt: 0, pauseAccumulated: 0, score: 0, combo: 0, maxCombo: 0, judged: 0, totalHitValue: 0, life: 100, laneFlash: [0,0,0,0], nextTick: 0, finished: false };
    this.held.clear(); this.effects = []; this.updateHud(); this.setStatus(this.chart ? `채보 ${this.chart.title} 로드 완료.` : '스페이스 또는 Start를 눌러 시작하세요.'); this.draw(0);
  }

  private async toggleStart(): Promise<void> {
    this.ensureAudio(); if (this.audioContext?.state === 'suspended') await this.audioContext.resume();
    const now = performance.now();
    if (!this.state.startedAt || this.state.finished) { if (this.state.finished) this.reset(); this.state.startedAt = now; this.state.running = true; this.setPlayFocus(true); if (this.audio.src) { this.audio.currentTime = 0; await this.audio.play(); } this.lastFrame = now; this.animationId = requestAnimationFrame((t) => this.loop(t)); return; }
    this.state.running = !this.state.running;
    if (this.state.running) { this.setPlayFocus(true); this.state.pauseAccumulated += now - this.state.pausedAt; if (this.audio.src) await this.audio.play(); this.lastFrame = now; this.animationId = requestAnimationFrame((t) => this.loop(t)); }
    else { this.setPlayFocus(false); this.state.pausedAt = now; this.audio.pause(); cancelAnimationFrame(this.animationId); this.draw(this.songTime()); this.setStatus('일시정지됨.'); }
  }

  private songTime(now = performance.now()): number { if (this.audio.src && this.state.startedAt) return this.audio.currentTime * 1000; if (!this.state.startedAt) return 0; const end = this.state.running ? now : this.state.pausedAt; return end - this.state.startedAt - this.state.pauseAccumulated; }
  private inputTime(): number { return Math.max(0, this.songTime() - this.latencyMs); }

  private onKeyDown(event: KeyboardEvent): void { if (event.repeat) return; const target = event.target; const typing = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement; if (!typing && event.code === 'Space') { event.preventDefault(); void this.toggleStart(); return; } if (!typing && event.key.toLowerCase() === 'r') { this.reset(); return; } const lane = LANE_KEYS.get(event.key.toLowerCase()); if (!typing && lane !== undefined) this.judge(lane); }
  private onKeyUp(event: KeyboardEvent): void { const lane = LANE_KEYS.get(event.key.toLowerCase()); if (lane !== undefined) this.release(lane); }

  private judge(lane: number): void {
    if (!this.state.running) return; const time = this.inputTime(); this.held.add(lane); this.state.laneFlash[lane] = 1; this.beep(330 + lane * 90);
    const candidate = this.state.notes.filter((n) => n.lane === lane && !n.hit && !n.missed).map((note) => ({ note, delta: Math.abs(note.time - time) })).filter(({ delta }) => delta <= judgementWindows.at(-1)!.ms).sort((a,b) => a.delta - b.delta)[0];
    if (!candidate) { this.miss('노트 없음'); return; }
    const judgement = judgementWindows.find((w) => candidate.delta <= w.ms)!; candidate.note.hit = true;
    if (candidate.note.duration > 0) { candidate.note.holding = true; this.effect(lane, 'Hold', '#72f6d1'); this.showJudgement('Hold', `${candidate.delta.toFixed(0)}ms`); return; }
    this.score(judgement, lane, candidate.delta);
  }
  private release(lane: number): void { this.held.delete(lane); const time = this.inputTime(); const note = this.state.notes.find((n) => n.lane === lane && n.holding && !n.completed && !n.missed); if (!note) return; const delta = Math.abs(note.time + note.duration - time); if (delta <= judgementWindows.at(-1)!.ms || time >= note.time + note.duration) this.completeLong(note, lane, delta); else { note.missed = true; note.holding = false; this.miss('롱노트 Break'); } }
  private completeLong(note: PlayableNote, lane: number, delta: number): void { note.completed = true; note.holding = false; const judgement = judgementWindows.find((w) => delta <= w.ms) ?? judgementWindows.at(-1)!; this.score(judgement, lane, delta, 1.35); }
  private score(j = judgementWindows[0], lane: number, delta: number, bonus = 1): void { this.state.combo++; this.state.maxCombo = Math.max(this.state.maxCombo, this.state.combo); this.state.score += (j.score + this.state.combo * 7) * bonus; this.state.life = Math.min(100, this.state.life + j.life); this.state.judged++; this.state.totalHitValue += j.score / 1000; this.effect(lane, j.name, j.color); this.showJudgement(j.name, `${delta.toFixed(0)}ms`); this.updateHud(); }
  private miss(detail: string): void { this.state.combo = 0; this.state.life = Math.max(0, this.state.life - difficulties[this.currentDifficulty].missDamage); this.state.judged++; this.showJudgement('Miss', detail); this.updateHud(); if (this.state.life <= 0) this.finish(); }

  private loop(now: number): void { const dt = Math.min(50, now - this.lastFrame); this.lastFrame = now; const time = this.songTime(now); this.state.laneFlash = this.state.laneFlash.map((v) => Math.max(0, v - dt / 120)); this.effects = this.effects.filter((e) => (e.age += dt) < 520);
    for (const note of this.state.notes) { if (note.missed || note.completed) continue; if (note.duration > 0 && note.holding && time >= note.time + note.duration && this.held.has(note.lane)) this.completeLong(note, note.lane, 0); if (!note.hit && time - note.time > judgementWindows.at(-1)!.ms) { note.missed = true; this.miss('지나감'); } }
    if (!this.audio.src) this.metronome(time); this.draw(time); const last = Math.max(0, ...this.state.notes.map((n) => n.time + n.duration)); if ((this.audio.src && this.audio.ended) || time > last + 1800) { this.finish(); return; } if (this.state.running) this.animationId = requestAnimationFrame((t) => this.loop(t)); }
  private finish(): void { this.state.running = false; this.state.finished = true; this.setPlayFocus(false); this.audio.pause(); cancelAnimationFrame(this.animationId); const acc = this.accuracy(); const rank = rankForAccuracy(acc); const songTitle = this.chart?.title || 'Demo Track'; const score = Math.round(this.state.score); addPlayRecord({ songTitle, difficulty: this.chart ? 'Custom' : difficulties[this.currentDifficulty].label, score, accuracy: acc, maxCombo: this.state.maxCombo, notes: this.state.notes.length, rank }); const best = bestRecord(songTitle); must<HTMLElement>('#resultRank').textContent = rank; must<HTMLElement>('#resultScore').textContent = score.toLocaleString('ko-KR'); must<HTMLElement>('#resultCombo').textContent = String(this.state.maxCombo); must<HTMLElement>('#resultAccuracy').textContent = `${acc.toFixed(2)}%`; must<HTMLElement>('#resultNotes').textContent = String(this.state.notes.length); must<HTMLElement>('#resultBest').textContent = best ? best.score.toLocaleString('ko-KR') : '-'; must<HTMLDialogElement>('#resultDialog').showModal(); }

  private draw(time: number): void { const ctx = this.ctx; ctx.clearRect(0,0,this.canvas.width,this.canvas.height); const grad = ctx.createLinearGradient(0,0,this.canvas.width,this.canvas.height); grad.addColorStop(0,'#111a35'); grad.addColorStop(1,'#060812'); ctx.fillStyle = grad; ctx.fillRect(0,0,this.canvas.width,this.canvas.height); const judgementX = 150; const spawnX = 1040; const laneTop = 96; const laneGap = 86; for (let lane=0; lane<4; lane++){ const y=laneTop+lane*laneGap; ctx.fillStyle=lane%2?'rgba(255,255,255,.035)':'rgba(255,255,255,.06)'; ctx.fillRect(64,y-34,this.canvas.width-110,68); ctx.fillStyle=`rgba(114,246,209,${.18+this.state.laneFlash[lane]*.45})`; ctx.fillRect(judgementX-34,y-34,68,68); ctx.fillStyle='#fff'; ctx.font='900 24px system-ui'; ctx.textAlign='center'; ctx.fillText(LANES[lane],judgementX,y+8); }
    ctx.strokeStyle='#72f6d1'; ctx.lineWidth=4; ctx.beginPath(); ctx.moveTo(judgementX,54); ctx.lineTo(judgementX,450); ctx.stroke(); const travelMs = 2200 / difficulties[this.currentDifficulty].speed; for (const note of this.state.notes){ if(note.completed||note.missed) continue; const x=judgementX+(note.time-time)/travelMs*(spawnX-judgementX); const y=laneTop+note.lane*laneGap; const endX=judgementX+(note.time+note.duration-time)/travelMs*(spawnX-judgementX); if (Math.max(x,endX)<40||Math.min(x,endX)>1120) continue; if(note.duration>0){ctx.strokeStyle=note.holding?'#72f6d1':'#ff5c9a'; ctx.lineWidth=16; ctx.beginPath(); ctx.moveTo(x,y); ctx.lineTo(endX,y); ctx.stroke();} ctx.fillStyle=note.duration>0?'#72f6d1':(note.lane%2?'#8bb8ff':'#ff5c9a'); ctx.beginPath(); ctx.arc(x,y,22,0,Math.PI*2); ctx.fill(); }
    for (const e of this.effects){ const y=laneTop+e.lane*laneGap; const p=e.age/520; ctx.globalAlpha=1-p; ctx.strokeStyle=e.color; ctx.lineWidth=4; ctx.beginPath(); ctx.arc(judgementX,y,36+p*42,0,Math.PI*2); ctx.stroke(); ctx.globalAlpha=1; } if(!this.state.running){ ctx.fillStyle='rgba(0,0,0,.34)'; ctx.fillRect(0,0,this.canvas.width,this.canvas.height); ctx.fillStyle='#eef3ff'; ctx.font='900 38px system-ui'; ctx.textAlign='center'; ctx.fillText(this.state.startedAt?'PAUSED':'READY',this.canvas.width/2,250); } }

  private metronome(time: number): void { const beatMs = 60000 / difficulties[this.currentDifficulty].bpm; if (time >= this.state.nextTick) { this.beep(Math.round(this.state.nextTick / beatMs) % 4 === 0 ? 220 : 165, .035, 'square', .45); this.state.nextTick += beatMs; } }
  private ensureAudio(): void { if (this.audioContext) return; this.audioContext = new AudioContext(); this.masterGain = this.audioContext.createGain(); this.masterGain.gain.value = .16; this.masterGain.connect(this.audioContext.destination); }
  private beep(freq = 440, duration = .055, type: OscillatorType = 'sine', volume = .8): void { if (!this.audioContext || !this.masterGain) return; const osc = this.audioContext.createOscillator(); const gain = this.audioContext.createGain(); osc.frequency.value = freq; osc.type = type; gain.gain.setValueAtTime(.001, this.audioContext.currentTime); gain.gain.exponentialRampToValueAtTime(volume, this.audioContext.currentTime + .006); gain.gain.exponentialRampToValueAtTime(.001, this.audioContext.currentTime + duration); osc.connect(gain).connect(this.masterGain); osc.start(); osc.stop(this.audioContext.currentTime + duration + .02); }
  private effect(lane: number, label: string, color: string): void { this.effects.push({ lane, label, color, age: 0 }); }
  private accuracy(): number { return this.state.judged ? (this.state.totalHitValue / this.state.judged) * 100 : 100; }
  private updateHud(): void { must<HTMLElement>('#songLabel').textContent = this.chart?.title || 'Demo Track'; must<HTMLElement>('#difficultyLabel').textContent = this.chart ? 'Custom' : difficulties[this.currentDifficulty].label; must<HTMLElement>('#score').textContent = Math.round(this.state.score).toLocaleString('ko-KR'); must<HTMLElement>('#combo').textContent = String(this.state.combo); must<HTMLElement>('#accuracy').textContent = `${this.accuracy().toFixed(2)}%`; must<HTMLElement>('#life').textContent = String(Math.round(this.state.life)); }
  private showJudgement(label: string, detail: string): void { must<HTMLElement>('#judgement').textContent = label; this.setStatus(detail); }
  private setStatus(text: string): void { must<HTMLElement>('#status').textContent = text; }
  private setPlayFocus(active: boolean): void { document.body.classList.toggle('is-playing', active); }
  private setAudioBlob(blob?: Blob): void { if (this.audioObjectUrl) URL.revokeObjectURL(this.audioObjectUrl); this.audioObjectUrl = null; if (!blob) { this.audio.removeAttribute('src'); this.audio.load(); return; } this.audioObjectUrl = URL.createObjectURL(blob); this.audio.src = this.audioObjectUrl; }
  private async renderLibrary(): Promise<void> { try { const songs = await getLibrary(); this.songLibrary.innerHTML = '<option value="">Demo Track</option>'; songs.forEach((song) => { const option = document.createElement('option'); option.value = song.id; option.textContent = `${song.title}${song.audioFileName ? ' · audio' : ''}`; this.songLibrary.append(option); }); } catch (error) { this.setStatus(`라이브러리 로드 실패: ${(error as Error).message}`); } }
  private async loadLibrarySong(): Promise<void> { const id = this.songLibrary.value; if (!id) { this.chart = null; this.setAudioBlob(); this.reset(); return; } const song = await getSong(id); if (!song) return; this.chart = song.chart; this.currentDifficulty = song.chart.difficulty; this.difficultySelect.value = this.currentDifficulty; this.setAudioBlob(song.audioBlob); this.reset(); }
  private async loadChartFile(): Promise<void> { const file = this.chartUpload.files?.[0]; if (!file) return; this.chart = parseChart(await file.text()); this.currentDifficulty = this.chart.difficulty; this.difficultySelect.value = this.currentDifficulty; this.reset(); }
  private loadAudioFile(): void { const file = this.audioUpload.files?.[0]; if (!file) return; this.setAudioBlob(file); this.setStatus(`${file.name} 로드 완료.`); }
}
