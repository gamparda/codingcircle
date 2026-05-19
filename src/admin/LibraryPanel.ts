import type { SongSummary } from '../library/storage';

interface LibraryPanelOptions {
  select: HTMLSelectElement;
  loadButton: HTMLButtonElement;
  deleteButton: HTMLButtonElement;
  onLoad: (id: string) => void | Promise<void>;
  onDelete: (id: string) => void | Promise<void>;
}

export class LibraryPanel {
  constructor(private readonly options: LibraryPanelOptions) {}

  bind(): void {
    this.options.loadButton.addEventListener('click', () => {
      const id = this.selectedId();
      if (id) void this.options.onLoad(id);
    });
    this.options.deleteButton.addEventListener('click', () => {
      const id = this.selectedId();
      if (id) void this.options.onDelete(id);
    });
  }

  render(songs: SongSummary[]): void {
    const previous = this.selectedId();
    this.options.select.innerHTML = '';
    songs.forEach((song) => {
      const option = document.createElement('option');
      option.value = song.id;
      option.textContent = `${song.title} · ${song.noteCount} notes${song.audioFileName ? ' · audio' : ''}`;
      this.options.select.append(option);
    });
    if (previous && songs.some((song) => song.id === previous)) this.options.select.value = previous;
  }

  selectedId(): string | null {
    return this.options.select.value || null;
  }
}
