import { LANES } from '../core/chart';
import type { ChartComment, ChartNote } from '../core/types';

interface TimelineOptions {
  canvas: HTMLCanvasElement;
  audio: HTMLAudioElement;
  getNotes: () => ChartNote[];
  getComments?: () => ChartComment[];
  getSelected: () => number;
  setSelected: (index: number) => void;
  replaceNote: (index: number, note: ChartNote) => void;
  addNote: (lane: number, time: number, duration: number) => void;
  getBpm: () => number;
  getOffset: () => number;
  getSnap: () => number;
  getLongDuration: () => number;
  onChange: () => void;
}

export class Timeline {
  private ctx: CanvasRenderingContext2D;
  private drag = -1;

  constructor(private readonly options: TimelineOptions) {
    const ctx = options.canvas.getContext('2d');
    if (!ctx) throw new Error('Timeline canvas context를 만들 수 없습니다.');
    this.ctx = ctx;
  }

  bind(): void {
    const { canvas } = this.options;
    canvas.addEventListener('pointerdown', (event) => this.onPointerDown(event));
    canvas.addEventListener('pointermove', (event) => this.onPointerMove(event));
    canvas.addEventListener('pointerup', () => { this.drag = -1; });
    canvas.addEventListener('pointercancel', () => { this.drag = -1; });
  }

  draw(): void {
    const { canvas } = this.options;
    const w = canvas.width;
    const h = canvas.height;
    const laneH = h / 4;
    const start = this.viewStart();
    const dur = this.durationView();
    const selected = this.options.getSelected();
    const notes = this.options.getNotes();

    this.ctx.clearRect(0, 0, w, h);
    this.ctx.fillStyle = '#080b15';
    this.ctx.fillRect(0, 0, w, h);

    for (let lane = 0; lane < 4; lane += 1) {
      this.ctx.fillStyle = lane % 2 ? 'rgba(255,255,255,.035)' : 'rgba(255,255,255,.06)';
      this.ctx.fillRect(0, lane * laneH, w, laneH - 1);
      this.ctx.fillStyle = '#fff';
      this.ctx.font = '900 16px system-ui';
      this.ctx.fillText(LANES[lane], 14, lane * laneH + laneH / 2 + 6);
    }

    this.drawBeatGrid(start, dur);
    this.options.getComments?.().forEach((comment) => {
      const x = (comment.time - start) / dur * w;
      if (x < -10 || x > w + 10) return;
      this.ctx.fillStyle = '#ffd166';
      this.ctx.beginPath();
      this.ctx.moveTo(x, 4);
      this.ctx.lineTo(x - 7, 18);
      this.ctx.lineTo(x + 7, 18);
      this.ctx.closePath();
      this.ctx.fill();
    });

    notes.forEach((note, index) => {
      const x = (note.time - start) / dur * w;
      const endX = (note.time + (note.duration || 0) - start) / dur * w;
      const y = note.lane * laneH + laneH / 2;
      if (endX < -20 || x > w + 20) return;
      this.ctx.strokeStyle = index === selected ? '#ffd166' : (note.duration ? '#72f6d1' : '#ff5c9a');
      this.ctx.fillStyle = this.ctx.strokeStyle;
      if (note.duration) {
        this.ctx.lineWidth = 10;
        this.ctx.lineCap = 'round';
        this.ctx.beginPath();
        this.ctx.moveTo(x, y);
        this.ctx.lineTo(endX, y);
        this.ctx.stroke();
      }
      this.ctx.beginPath();
      this.ctx.arc(x, y, 9, 0, Math.PI * 2);
      this.ctx.fill();
    });

    const playX = (this.currentTime() - start) / dur * w;
    this.ctx.strokeStyle = '#fff';
    this.ctx.lineWidth = 2;
    this.ctx.beginPath();
    this.ctx.moveTo(playX, 0);
    this.ctx.lineTo(playX, h);
    this.ctx.stroke();
  }

  private currentTime(): number { return this.options.audio.currentTime * 1000; }
  private durationView(): number { return Math.max(8000, (this.options.audio.duration || 32) * 1000) / 2.4; }
  private viewStart(): number { return Math.max(0, this.currentTime() - this.durationView() * .42); }

  private snapTime(time: number): number {
    const snap = this.options.getSnap();
    if (!snap) return Math.max(0, Math.round(time));
    const step = 60000 / this.options.getBpm() * 4 / snap;
    return Math.max(0, Math.round(Math.round((time - this.options.getOffset()) / step) * step + this.options.getOffset()));
  }

  private drawBeatGrid(start: number, dur: number): void {
    const snap = this.options.getSnap() || 4;
    const step = 60000 / this.options.getBpm() * 4 / snap;
    const first = Math.floor((start - this.options.getOffset()) / step) * step + this.options.getOffset();
    for (let t = first; t < start + dur; t += step) {
      const x = (t - start) / dur * this.options.canvas.width;
      this.ctx.strokeStyle = 'rgba(114,246,209,.22)';
      this.ctx.lineWidth = 1;
      this.ctx.beginPath();
      this.ctx.moveTo(x, 0);
      this.ctx.lineTo(x, this.options.canvas.height);
      this.ctx.stroke();
    }
  }

  private eventPos(event: PointerEvent): { lane: number; time: number } {
    const rect = this.options.canvas.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width * this.options.canvas.width;
    const y = (event.clientY - rect.top) / rect.height * this.options.canvas.height;
    return {
      lane: Math.max(0, Math.min(3, Math.floor(y / (this.options.canvas.height / 4)))),
      time: this.snapTime(this.viewStart() + x / this.options.canvas.width * this.durationView()),
    };
  }

  private findNote(event: PointerEvent): number {
    const pos = this.eventPos(event);
    let best = -1;
    let delta = Infinity;
    this.options.getNotes().forEach((note, index) => {
      const d = Math.abs(note.time - pos.time) + (note.lane === pos.lane ? 0 : 1200);
      if (d < delta && d < 650) { best = index; delta = d; }
    });
    return best;
  }

  private onPointerDown(event: PointerEvent): void {
    const found = this.findNote(event);
    if (found >= 0) {
      this.options.setSelected(found);
      this.drag = found;
    } else {
      const pos = this.eventPos(event);
      this.options.addNote(pos.lane, pos.time, event.shiftKey ? this.options.getLongDuration() : 0);
      this.drag = this.options.getSelected();
    }
    this.options.canvas.setPointerCapture(event.pointerId);
    this.options.onChange();
  }

  private onPointerMove(event: PointerEvent): void {
    if (this.drag < 0) return;
    const pos = this.eventPos(event);
    this.options.replaceNote(this.drag, { ...this.options.getNotes()[this.drag], lane: pos.lane, time: pos.time });
    this.options.onChange();
  }
}
