import { LANES } from '../core/chart';
import type { ChartNote } from '../core/types';

interface ChartListOptions {
  list: HTMLOListElement;
  getNotes: () => ChartNote[];
  getSelected: () => number;
  removeNote: (index: number) => void;
  onChange: () => void;
}

export class ChartList {
  constructor(private readonly options: ChartListOptions) {}

  bind(): void {
    this.options.list.addEventListener('click', (event) => {
      const button = (event.target as Element).closest<HTMLButtonElement>('[data-remove]');
      if (!button) return;
      this.options.removeNote(Number(button.dataset.remove));
      this.options.onChange();
    });
  }

  render(): void {
    this.options.list.innerHTML = '';
    this.options.getNotes().slice(0, 140).forEach((note, index) => {
      const row = document.createElement('li');
      row.innerHTML = `<button data-remove="${index}">×</button><span>${(note.time / 1000).toFixed(3)}s</span><strong>${LANES[note.lane]}</strong><em>${note.duration ? `${note.duration}ms` : 'tap'}</em>`;
      if (index === this.options.getSelected()) row.style.outline = '2px solid var(--accent)';
      this.options.list.append(row);
    });
  }
}
