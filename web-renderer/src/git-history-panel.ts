import {
  collectBlocks,
  computeBlockChanges,
  clearReviewDom,
  inlineDiff,
} from './review-mode';
import type { ReviewChange } from './review-mode';

/**
 * Right-side Git history panel for the open file.
 *
 * The module renders the commit list. It sends the selected entry to Swift.
 * Swift answers with the two revisions. `applyGitDiff` then marks the rendered
 * document with the inline word marks of `review-mode`. It does not use the
 * review toolbar and the reviewed store.
 */

export interface GitHistoryEntry {
  id: string;
  shortHash: string;
  author: string;
  date: string;
  subject: string;
  kind: 'commit' | 'working';
  path?: string;
}

export interface GitHistoryPayload {
  available: boolean;
  reason?: string;
  repositoryRoot?: string;
  entries: GitHistoryEntry[];
}

export interface GitDiffContext {
  currentBody: string;
  baselineBody: string;
  renderBaseline: (body: string) => string;
  log?: (message: string) => void;
}

const REASON_MESSAGES: Record<string, string> = {
  'not-a-repository': 'No Git repository found for this file.',
  'no-access': 'FluxMarkdown cannot read this repository folder.',
  'command-failed': 'Git could not read this repository.',
};

interface GitHistoryBridge {
  webkit?: {
    messageHandlers?: {
      gitHistory?: { postMessage: (payload: unknown) => void };
    };
  };
}

/** Format an ISO date as a short relative time. */
export function formatRelativeDate(iso: string, now: Date = new Date()): string {
  if (!iso) return '';
  const then = new Date(iso);
  if (Number.isNaN(then.getTime())) return '';
  const seconds = Math.round((now.getTime() - then.getTime()) / 1000);
  if (seconds < 60) return 'just now';
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} h ago`;
  const days = Math.round(hours / 24);
  if (days < 30) return `${days} d ago`;
  const months = Math.round(days / 30);
  if (months < 12) return `${months} mo ago`;
  return `${Math.round(months / 12)} y ago`;
}

export class GitHistoryPanel {
  private readonly log?: (message: string) => void;
  private container: HTMLElement | null = null;
  private list: HTMLElement | null = null;
  private toggleButton: HTMLElement | null = null;
  private payload: GitHistoryPayload | null = null;
  private selectedId: string | null = null;
  private visible = false;

  constructor(log?: (message: string) => void) {
    this.log = log;
  }

  render(payload: GitHistoryPayload): void {
    this.payload = payload;
    this.ensureDom();
    this.renderList();
  }

  setSelected(id: string): void {
    this.selectedId = id;
    if (!this.list) return;
    this.list.querySelectorAll<HTMLElement>('[data-git-entry]').forEach((el) => {
      el.classList.toggle('is-selected', el.getAttribute('data-git-entry') === id);
    });
  }

  private showCurrent(): void {
    this.setSelected('');
    this.postAction('current');
  }

  isVisible(): boolean {
    return this.visible;
  }

  toggle(): void {
    this.setVisible(!this.visible);
  }

  setVisible(visible: boolean): void {
    this.visible = visible;
    this.container?.setAttribute('data-visible', String(visible));
    this.toggleButton?.setAttribute('data-active', String(visible));
    this.toggleButton?.setAttribute('aria-expanded', String(visible));
    document.body.classList.toggle('git-history-open', visible);
  }

  private ensureDom(): void {
    if (this.container) return;

    const container = document.createElement('aside');
    container.id = 'git-history-panel';
    container.setAttribute('data-visible', 'false');
    container.setAttribute('aria-label', 'Git history');

    const header = document.createElement('div');
    header.className = 'git-history-header';

    const title = document.createElement('span');
    title.className = 'git-history-title';
    title.textContent = 'Git history';

    const backButton = document.createElement('button');
    backButton.type = 'button';
    backButton.className = 'git-history-back';
    backButton.textContent = '↩';
    backButton.title = 'Show the current file';
    backButton.addEventListener('click', () => this.showCurrent());

    const closeButton = document.createElement('button');
    closeButton.type = 'button';
    closeButton.className = 'git-history-close';
    closeButton.textContent = '×';
    closeButton.title = 'Hide Git history';
    closeButton.addEventListener('click', () => this.setVisible(false));

    header.appendChild(title);
    header.appendChild(backButton);
    header.appendChild(closeButton);

    const list = document.createElement('div');
    list.className = 'git-history-list';

    container.appendChild(header);
    container.appendChild(list);
    document.body.appendChild(container);

    const toggle = document.createElement('button');
    toggle.id = 'git-history-toggle';
    toggle.type = 'button';
    toggle.className = 'git-history-toggle';
    toggle.title = 'Toggle Git history';
    toggle.setAttribute('aria-label', 'Toggle Git history');
    toggle.setAttribute('data-active', 'false');
    toggle.setAttribute('aria-expanded', 'false');
    toggle.innerHTML = `
        <svg width="20" height="20" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
            <path d="M9.5 3.25a2.25 2.25 0 1 1 3 2.122V6A2.5 2.5 0 0 1 10 8.5H6a1 1 0 0 0-1 1v1.128a2.251 2.251 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.5 0v1.836A2.492 2.492 0 0 1 6 7h4a1 1 0 0 0 1-1v-.628A2.25 2.25 0 0 1 9.5 3.25Zm-6 0a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Zm8.25-.75a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5ZM4.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z"/>
        </svg>`;
    toggle.addEventListener('click', () => this.toggle());
    document.body.appendChild(toggle);

    this.container = container;
    this.list = list;
    this.toggleButton = toggle;
  }

  private renderList(): void {
    if (!this.list) return;
    this.list.innerHTML = '';

    const payload = this.payload;
    if (!payload) return;

    if (!payload.available) {
      this.list.appendChild(
        this.makeMessage(REASON_MESSAGES[payload.reason ?? ''] ?? 'Git history is not available.')
      );
      return;
    }
    if (payload.entries.length === 0) {
      this.list.appendChild(this.makeMessage('No history for this file.'));
      return;
    }
    for (const entry of payload.entries) {
      this.list.appendChild(this.makeEntry(entry));
    }
  }

  private makeMessage(text: string): HTMLElement {
    const message = document.createElement('div');
    message.className = 'git-history-message';
    message.textContent = text;
    return message;
  }

  private makeEntry(entry: GitHistoryEntry): HTMLElement {
    const el = document.createElement('button');
    el.type = 'button';
    el.className = 'git-history-entry';
    el.setAttribute('data-git-entry', entry.id);
    if (entry.kind === 'working') el.classList.add('is-working');
    if (entry.id === this.selectedId) el.classList.add('is-selected');

    const top = document.createElement('div');
    top.className = 'git-history-entry-top';

    const hash = document.createElement('span');
    hash.className = 'git-history-hash';
    hash.textContent = entry.kind === 'working' ? 'Uncommitted' : entry.shortHash;

    const date = document.createElement('span');
    date.className = 'git-history-date';
    date.textContent = entry.kind === 'working' ? '' : formatRelativeDate(entry.date);

    top.appendChild(hash);
    top.appendChild(date);

    const subject = document.createElement('div');
    subject.className = 'git-history-subject';
    subject.textContent = entry.subject || '(no subject)';

    el.appendChild(top);
    el.appendChild(subject);

    if (entry.kind !== 'working') {
      const author = document.createElement('div');
      author.className = 'git-history-author';
      author.textContent = entry.author;
      el.appendChild(author);
    }

    el.addEventListener('click', () => {
      this.setSelected(entry.id);
      this.postSelect(entry);
    });
    return el;
  }

  private postSelect(entry: GitHistoryEntry): void {
    this.post({ action: 'select', id: entry.id, kind: entry.kind, hash: entry.id, path: entry.path ?? '' });
  }

  private postAction(action: string): void {
    this.post({ action });
  }

  private post(payload: Record<string, string>): void {
    const bridge = window as unknown as GitHistoryBridge;
    try {
      bridge.webkit?.messageHandlers?.gitHistory?.postMessage(payload);
    } catch (error) {
      this.log?.(`GitHistoryPanel: post failed: ${String(error)}`);
    }
  }
}

function inlineBefore(baselineEl: HTMLElement): HTMLElement {
  const wrap = document.createElement('div');
  wrap.className = 'review-inline-before';
  wrap.appendChild(baselineEl.cloneNode(true));
  return wrap;
}

function applyChange(container: HTMLElement, change: ReviewChange): void {
  if (change.type === 'removed') {
    if (!change.baselineEl) return;
    const item = document.createElement('div');
    item.className = 'review-item review-removed';
    item.setAttribute('data-git-diff-id', change.id);
    item.appendChild(inlineBefore(change.baselineEl));
    const anchor = change.insertBefore;
    if (anchor && anchor.parentNode) {
      anchor.parentNode.insertBefore(item, anchor);
    } else {
      container.appendChild(item);
    }
    return;
  }

  const blockEl = change.el;
  if (!blockEl) return;

  const item = document.createElement('div');
  item.className = `review-item review-${change.type}`;
  item.setAttribute('data-git-diff-id', change.id);

  if (change.type === 'modified' && change.baselineEl) {
    const annotated = inlineDiff(change.baselineEl.innerHTML, blockEl.innerHTML);
    if (annotated === null) {
      item.appendChild(inlineBefore(change.baselineEl));
    } else {
      blockEl.innerHTML = annotated;
    }
  }

  blockEl.parentNode?.insertBefore(item, blockEl);
  item.appendChild(blockEl);
}

/**
 * Mark `container` with the inline diff of `currentBody` against
 * `baselineBody`. Return the number of changed blocks.
 */
export function applyGitDiff(container: HTMLElement, context: GitDiffContext): number {
  clearReviewDom(container);

  const baselineRoot = document.createElement('div');
  baselineRoot.innerHTML = context.renderBaseline(context.baselineBody);

  const currentBlocks = collectBlocks(container);
  const baselineBlocks = collectBlocks(baselineRoot);
  const changes = computeBlockChanges(currentBlocks, baselineBlocks);

  for (const change of changes) {
    applyChange(container, change);
  }
  context.log?.(`[git-diff] marks=${changes.length}`);
  return changes.length;
}
