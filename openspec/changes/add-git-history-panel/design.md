---
title: "Design: Git history panel"
date: 2026-10-12
tags:
  - git-history
  - design
  - inline-diff
  - app-sandbox
---

# Design: Git history panel

## Context

The main app is not sandboxed. The app opens a file from disk and has the file URL. The web renderer exposes `window.renderMarkdown`. The `add-review-mode` change adds a block diff and inline word marks.

## Decisions

### Repository detection

The app asks Git for the repository root of the file folder:
`git rev-parse --show-toplevel`.
Git walks up the folder tree. The app rejects a `.git` file, because the spec excludes a linked worktree and a submodule.
This call uses the same 3-second timeout as every other Git call.
The app does not read the parent folders with Foundation, because that read can block.

### Git process

The app runs `/usr/bin/git` with `Process`. The app sets this environment:

- `GIT_CONFIG_NOSYSTEM=1`
- `GIT_TERMINAL_PROMPT=0`
- `GIT_OPTIONAL_LOCKS=0`
- `LC_ALL=C`
- `HOME` = the temporary directory of the app container

The app applies a 3-second timeout. The app kills the process on a timeout. The app sets the working directory to the repository root.

### Commands

The app uses these commands:

- History with renames and paths:
  `git log -n 10 --follow --name-only --format=<fields> -- <relativePath>`
- Content of a revision:
  `git show <hash>:<pathAtCommit>`
- Content of the parent revision:
  `git show <hash>^:<pathAtParent>`
- Uncommitted change:
  - current = the on-disk file
  - baseline = `git show HEAD:<relativePath>`
  - test = `git status --porcelain -- <relativePath>`

A root commit has no parent. The parent command fails. The app uses an empty baseline.

### Data transfer

The app sends one payload to the web renderer:

`window.setGitHistory({ available, reason, entries })`

`entries` is a list. Each entry has `id`, `shortHash`, `author`, `date`, `subject`, and `kind`. The `kind` is `commit` or `working`.

The web renderer sends a selection message to Swift:

`window.webkit.messageHandlers.gitHistory.postMessage({ action: "select", id })`

The app fetches the two revisions. The app calls:

`window.showGitDiff({ id, current, baseline, meta })`

`window.clearGitDiff()` restores the current document.

### Panel layout

The panel is on the right side. The panel is hidden by default. A control in the corner shows and hides the panel. The list is read-only. A selected entry has a highlight. A disabled entry shows a short reason.

### Inline diff

The panel reuses `diffBlocks` and the inline word marks from `add-review-mode`. The panel does NOT use the reviewed store and the review toolbar. The panel uses the "before" disclosure for a removed block and for a large rewrite. The display uses the existing `data-source-line` attributes.

### Sandbox access

The app catches a read error. The app sends `available: false` with a reason. The panel shows the reason.

### Performance

The app starts the Git work after the first render. The app runs the work on a background queue. The panel does not block the first paint.
