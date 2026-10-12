---
title: "Tasks: Git history panel"
date: 2026-10-12
tags:
  - git-history
  - tasks
---

# Tasks

## 1. Repository detection and Git runner

- [x] 1.1 Write tests for repository detection. Walk up the folders and find a `.git` directory.
- [x] 1.2 Implement `GitHistoryProvider.findRepository(for:)`.
- [x] 1.3 Write tests for the safe environment and the timeout.
- [x] 1.4 Implement the Git process runner with the environment, the timeout, and the exit-code check.
- [x] 1.5 Write tests for the history parse. Read the hash, the author, the date, the subject, and the path.
- [x] 1.6 Implement `history(limit: 10)` with `--follow`.
- [x] 1.7 Write tests for the content of a revision and the parent revision.
- [x] 1.8 Implement `content(at:)` and `parentContent(of:)`. Use an empty string for the root commit.
- [x] 1.9 Write tests for the uncommitted change. Detect it with `git status --porcelain`.
- [x] 1.10 Implement the working-tree entry.

## 2. Extension integration

- [x] 2.1 Add the read-only temporary exception for the home folder to `MarkdownPreviewRelease.entitlements`.
- [x] 2.2 Detect the repository in `preparePreviewOfFile`. Start the work on a background queue after the first render.
- [x] 2.3 Send `window.setGitHistory` with the payload. Handle the no-access and no-repo cases.
- [x] 2.4 Add the `gitHistory` message handler. On select, fetch the revisions and call `window.showGitDiff`.
- [x] 2.5 Write tests for the payload builder.

## 3. Web renderer panel

- [x] 3.1 Write tests for the panel. Render the entries and the header.
- [x] 3.2 Implement `git-history-panel.ts` and the styles. Hide the panel by default.
- [x] 3.3 Write tests for the show and hide control.
- [x] 3.4 Implement the show and hide control.
- [x] 3.5 Write tests for the entry selection. Post the select message.
- [x] 3.6 Implement the selection and the highlight.
- [x] 3.7 Write tests for `showGitDiff`. Reuse the inline marks. Do not show the review controls.
- [x] 3.8 Implement `window.setGitHistory`, `window.showGitDiff`, and `window.clearGitDiff`.
- [x] 3.9 Show the reason when the history is not available.

## 4. Verification

- [x] 4.1 Run `npm test` and `npm run build` in `web-renderer`.
- [ ] 4.2 Run the Swift tests with a temporary Git repository fixture. Cannot run here: no Xcode on this machine (`xcodebuild` needs full Xcode).
- [ ] 4.3 Measure the cold start. Confirm the panel does not change the first render. Cannot run here: no Xcode on this machine.
- [x] 4.4 Update `CHANGELOG.md` under `[Unreleased]`.
