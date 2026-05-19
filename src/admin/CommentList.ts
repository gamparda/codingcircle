import type { ChartComment } from '../core/types';

interface CommentListOptions {
  list: HTMLOListElement;
  getComments: () => ChartComment[];
  removeComment: (index: number) => void;
  onJump: (time: number) => void;
  onChange: () => void;
}

export class CommentList {
  constructor(private readonly options: CommentListOptions) {}

  bind(): void {
    this.options.list.addEventListener('click', (event) => {
      const remove = (event.target as Element).closest<HTMLButtonElement>('[data-remove-comment]');
      if (remove) { this.options.removeComment(Number(remove.dataset.removeComment)); this.options.onChange(); return; }
      const jump = (event.target as Element).closest<HTMLButtonElement>('[data-jump-comment]');
      if (jump) this.options.onJump(Number(jump.dataset.jumpComment));
    });
  }

  render(): void {
    this.options.list.innerHTML = '';
    this.options.getComments().forEach((comment, index) => {
      const row = document.createElement('li');
      row.innerHTML = `<button data-remove-comment="${index}">×</button><button data-jump-comment="${comment.time}">${(comment.time / 1000).toFixed(2)}s</button><span>${comment.text}</span>`;
      this.options.list.append(row);
    });
  }
}
