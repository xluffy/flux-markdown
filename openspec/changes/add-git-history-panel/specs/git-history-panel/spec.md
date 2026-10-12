---
title: "Spec: Git history panel"
date: 2026-10-12
tags:
  - git-history
  - spec
  - inline-diff
---

## ADDED Requirements

### Requirement: Repository detection

The extension SHALL detect the Git repository root of the previewed file. The extension SHALL ask Git for the root with one bounded call. The extension SHALL NOT detect a `.git` file.

#### Scenario: File in a repository

- **WHEN** the file is inside a Git work tree
- **THEN** the extension sets the repository root to the path that the Git command reports

#### Scenario: File not in a repository

- **WHEN** no parent folder of the file is a Git work tree
- **THEN** the extension sends `available: false` and shows no history entry

#### Scenario: `.git` is a file

- **WHEN** the parent folder contains a `.git` file and no `.git` directory
- **THEN** the extension sends `available: false`

### Requirement: History list

The extension SHALL show the history of the open file in a right-side panel. The panel SHALL be hidden by default. The extension SHALL limit the list to 10 commits. Each entry SHALL show the short hash, the author, the relative date, and the subject. The extension SHALL follow file renames.

#### Scenario: Show the panel

- **WHEN** the user uses the show control
- **THEN** the panel appears on the right side

#### Scenario: Hide the panel

- **WHEN** the user uses the hide control
- **THEN** the panel disappears and the document uses the full width

#### Scenario: Limit

- **WHEN** the file has more than 10 commits
- **THEN** the list shows the 10 most recent commits

#### Scenario: Follow a rename

- **WHEN** the file moved in an earlier commit
- **THEN** the list contains the commits from before the move

### Requirement: Uncommitted change entry

The extension SHALL add one entry for uncommitted changes. The entry SHALL compare the working tree file to `HEAD`. The extension SHALL show the entry only when `git status --porcelain` reports a change for the file.

#### Scenario: Uncommitted change exists

- **WHEN** the working tree file differs from `HEAD`
- **THEN** the list shows one uncommitted entry above the commits

#### Scenario: No uncommitted change

- **WHEN** the working tree file equals `HEAD`
- **THEN** the list shows no uncommitted entry

#### Scenario: Untracked file

- **WHEN** Git does not track the file
- **THEN** the extension shows no history and no uncommitted entry

### Requirement: Inline diff of a selected revision

The extension SHALL show the content of the selected revision. The extension SHALL show an inline diff against the parent revision. The extension SHALL reuse the inline word marks of `add-review-mode`. The extension SHALL NOT show the review controls and the reviewed store. The extension SHALL use an empty baseline for the root commit.

#### Scenario: Select a commit

- **WHEN** the user selects a commit
- **THEN** the extension fetches the commit content and the parent content and shows the inline diff

#### Scenario: Select the uncommitted entry

- **WHEN** the user selects the uncommitted entry
- **THEN** the extension shows the inline diff of the working tree file against `HEAD`

#### Scenario: Root commit

- **WHEN** the selected commit has no parent
- **THEN** the extension uses an empty baseline and the renderer marks all content as added

#### Scenario: Removed block

- **WHEN** a parent block does not exist in the selected revision
- **THEN** the renderer shows the parent block in a "before" disclosure

#### Scenario: Return to the current file

- **WHEN** the user uses the back control
- **THEN** the renderer shows the current on-disk file without diff marks

### Requirement: Access failure message

The extension SHALL catch a repository read error. The extension SHALL send `available: false` with a reason. The panel SHALL show the reason.

#### Scenario: Sandbox denies access

- **WHEN** the extension cannot read the repository
- **THEN** the panel shows a message that explains the missing access

### Requirement: Background load

The extension SHALL start the Git work after the first render. The extension SHALL run the Git work on a background queue. The panel SHALL NOT delay the first render.

#### Scenario: Slow Git work

- **WHEN** a Git command takes time
- **THEN** the Markdown document appears before the panel data

### Requirement: Print and export

The renderer SHALL hide the panel in print output. The renderer SHALL remove the panel from HTML export output.

#### Scenario: Print

- **WHEN** the user prints the document
- **THEN** the panel does not appear

#### Scenario: HTML export

- **WHEN** the user exports the document to HTML
- **THEN** the panel and the diff marks do not appear
