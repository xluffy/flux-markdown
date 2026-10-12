import {
  applyGitDiff,
  formatRelativeDate,
  GitHistoryPanel,
} from '../src/git-history-panel';
import type { GitHistoryPayload } from '../src/git-history-panel';

function block(tag: string, text: string, start: number, end: number): string {
  return `<${tag} data-source-line="${start}" data-source-line-end="${end}">${text}</${tag}>`;
}

function makeContainer(html: string): HTMLElement {
  const container = document.createElement('div');
  container.innerHTML = html;
  document.body.appendChild(container);
  return container;
}

function payload(entries: GitHistoryPayload['entries']): GitHistoryPayload {
  return { available: true, entries };
}

function makePayload(): GitHistoryPayload {
  return payload([
    {
      id: 'working',
      shortHash: 'working',
      author: '',
      date: '',
      subject: 'Uncommitted changes',
      kind: 'working',
      path: 'docs/readme.md',
    },
    {
      id: 'abc123',
      shortHash: 'abc123',
      author: 'Alice',
      date: new Date().toISOString(),
      subject: 'Fix the typo',
      kind: 'commit',
      path: 'docs/readme.md',
    },
  ]);
}

interface Posted {
  action: string;
  id?: string;
  kind?: string;
  hash?: string;
  path?: string;
}

function installBridge(): Posted[] {
  const posted: Posted[] = [];
  const windowWithBridge = window as unknown as {
    webkit: { messageHandlers: { gitHistory: { postMessage: (p: Posted) => void } } };
  };
  windowWithBridge.webkit = {
    messageHandlers: {
      gitHistory: {
        postMessage: (p: Posted) => posted.push(p),
      },
    },
  };
  return posted;
}

beforeEach(() => {
  document.body.innerHTML = '';
  delete (window as unknown as { webkit?: unknown }).webkit;
});

describe('formatRelativeDate', () => {
  const now = new Date('2026-06-01T12:00:00Z');

  test('formats recent times', () => {
    expect(formatRelativeDate(new Date('2026-06-01T11:59:30Z').toISOString(), now)).toBe('just now');
    expect(formatRelativeDate(new Date('2026-06-01T11:30:00Z').toISOString(), now)).toBe('30 min ago');
    expect(formatRelativeDate(new Date('2026-06-01T06:00:00Z').toISOString(), now)).toBe('6 h ago');
    expect(formatRelativeDate(new Date('2026-05-29T12:00:00Z').toISOString(), now)).toBe('3 d ago');
  });

  test('returns an empty string for a missing or bad date', () => {
    expect(formatRelativeDate('')).toBe('');
    expect(formatRelativeDate('not-a-date')).toBe('');
  });
});

describe('GitHistoryPanel', () => {
  test('creates a hidden panel with a toggle', () => {
    const panel = new GitHistoryPanel();
    panel.render(makePayload());
    const container = document.getElementById('git-history-panel');
    const toggle = document.getElementById('git-history-toggle');
    expect(container).toBeTruthy();
    expect(container?.getAttribute('data-visible')).toBe('false');
    expect(toggle).toBeTruthy();
    expect(panel.isVisible()).toBe(false);
  });

  test('renders the hash, author, and subject of each entry', () => {
    const panel = new GitHistoryPanel();
    panel.render(makePayload());
    const entries = document.querySelectorAll('.git-history-entry');
    expect(entries).toHaveLength(2);
    expect(entries[0].textContent).toContain('Uncommitted');
    expect(entries[1].textContent).toContain('abc123');
    expect(entries[1].textContent).toContain('Fix the typo');
    expect(entries[1].textContent).toContain('Alice');
  });

  test('the toggle shows and hides the panel', () => {
    const panel = new GitHistoryPanel();
    panel.render(makePayload());
    const toggle = document.getElementById('git-history-toggle') as HTMLButtonElement;
    toggle.click();
    expect(panel.isVisible()).toBe(true);
    expect(document.getElementById('git-history-panel')?.getAttribute('data-visible')).toBe('true');
    toggle.click();
    expect(panel.isVisible()).toBe(false);
  });

  test('the close control hides the panel', () => {
    const panel = new GitHistoryPanel();
    panel.render(makePayload());
    panel.setVisible(true);
    (document.querySelector('.git-history-close') as HTMLButtonElement).click();
    expect(panel.isVisible()).toBe(false);
  });

  test('selecting an entry posts the message and highlights the entry', () => {
    const posted = installBridge();
    const panel = new GitHistoryPanel();
    panel.render(makePayload());
    (document.querySelectorAll('.git-history-entry')[1] as HTMLButtonElement).click();
    expect(posted).toHaveLength(1);
    expect(posted[0]).toEqual({ action: 'select', id: 'abc123', kind: 'commit', hash: 'abc123', path: 'docs/readme.md' });
    expect(document.querySelectorAll('.git-history-entry')[1].classList.contains('is-selected')).toBe(true);
  });

  test('the back control posts the current action and clears the selection', () => {
    const posted = installBridge();
    const panel = new GitHistoryPanel();
    panel.render(makePayload());
    (document.querySelectorAll('.git-history-entry')[1] as HTMLButtonElement).click();
    (document.querySelector('.git-history-back') as HTMLButtonElement).click();
    expect(posted).toHaveLength(2);
    expect(posted[1]).toEqual({ action: 'current' });
    expect(document.querySelectorAll('.git-history-entry[data-git-entry="abc123"]')[0].classList.contains('is-selected')).toBe(false);
  });

  test('shows a reason when the history is not available', () => {
    const panel = new GitHistoryPanel();
    panel.render({ available: false, reason: 'no-access', entries: [] });
    expect(document.querySelector('.git-history-message')?.textContent).toContain('cannot read');
  });

  test('shows an empty message when the file has no history', () => {
    const panel = new GitHistoryPanel();
    panel.render(payload([]));
    expect(document.querySelector('.git-history-message')?.textContent).toContain('No history');
  });
});

describe('applyGitDiff', () => {
  test('marks added words without the review controls', () => {
    const container = makeContainer(block('p', 'hello brave world', 1, 1));
    const count = applyGitDiff(container, {
      currentBody: '',
      baselineBody: '',
      renderBaseline: () => block('p', 'hello world', 1, 1),
    });
    expect(count).toBe(1);
    expect(container.querySelector('.review-word-added')).toBeTruthy();
    expect(container.querySelector('.review-toolbar')).toBeNull();
    expect(container.querySelector('.review-footer')).toBeNull();
    expect(container.querySelector('.review-check')).toBeNull();
  });

  test('shows a removed block inline', () => {
    const container = makeContainer(block('p', 'kept', 1, 1));
    const count = applyGitDiff(container, {
      currentBody: '',
      baselineBody: '',
      renderBaseline: () => block('p', 'kept', 1, 1) + block('p', 'gone', 3, 3),
    });
    expect(count).toBe(1);
    expect(container.querySelector('.review-inline-before')?.textContent).toContain('gone');
  });

  test('clears previous marks before it applies new ones', () => {
    const container = makeContainer(block('p', 'hello brave world', 1, 1));
    applyGitDiff(container, {
      currentBody: '',
      baselineBody: '',
      renderBaseline: () => block('p', 'hello world', 1, 1),
    });
    applyGitDiff(container, {
      currentBody: '',
      baselineBody: '',
      renderBaseline: () => block('p', 'hello brave world', 1, 1),
    });
    expect(container.querySelectorAll('.review-item')).toHaveLength(0);
  });
});
