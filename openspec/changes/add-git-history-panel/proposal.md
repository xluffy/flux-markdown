---
title: "Change: Add a Git history panel for the open file"
date: 2026-10-12
tags:
  - git-history
  - quicklook-extension
  - markdown-preview
  - inline-diff
---

# Change: Add a Git history panel for the open file

## Why

A reviewer wants to understand the recent changes of a Markdown file. Today the reviewer must leave the Finder preview and open a terminal. This change shows the Git history of the open file inside the preview. The reviewer selects a revision and reads the inline diff. The reviewer compares the change to the previous revision without a second tool.

## What Changes

- Detect the Git repository of the open file. Check for a `.git` directory in the file folder or in a parent folder. Use `/usr/bin/git` as the data source.
- Add a right-side panel. The panel lists the recent history of the open file. The panel is hidden by default. A control shows and hides the panel.
- Limit the list to 10 commits. Show the short hash, the author, the relative date, and the subject of each commit.
- Add one entry for uncommitted changes. The entry compares the working tree file to `HEAD`.
- Follow file renames.
- Select an entry. The renderer shows the content of that revision with an inline diff against the parent revision. Reuse the diff engine of `add-review-mode`.
- Show a clear message when the extension cannot read the repository.
- Run the Git commands in the background after the first render.

This change does NOT:

- show a file that Git does not track,
- support a `.git` file (worktree or submodule),
- show a full patch, a code diff, or a two-column diff,
- show a document minimap.

## Access decision

The main app is not sandboxed. It reads the repository and runs `/usr/bin/git` directly. The QuickLook extension does not load Git history and does not need a home-folder read exception. The panel shows a reason when a read fails.

## Impact

- Affected specs: `git-history-panel` (new)
- Affected code:
  - `Sources/Shared/GitHistoryProvider.swift` (new)
  - `Sources/Markdown/MarkdownWebView.swift` (main app: detect, fetch, bridge)
  - `web-renderer/src/git-history-panel.ts` (new)
  - `web-renderer/src/styles/git-history-panel.css` (new)
  - `web-renderer/src/index.ts` (render hook and JS API)
  - `web-renderer/test/git-history-panel.test.ts` (new)
  - `Tests/MarkdownTests/GitHistoryProviderTests.swift` (new)
- Dependency: `add-review-mode`. This change reuses the block diff and the inline word marks.
