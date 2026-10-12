---
title: "Large Block Change - Before"
date: 2026-01-05
tags:
  - review-mode
  - fixture
  - large-block-change
---

# Large Block Change Test

This fixture tests one large block change. Use it with `block-change-after.md`.

The first paragraph has a small edit. Only one word changes here, so the renderer marks one word inline.

The second paragraph changes in total. The whole block is replaced. This text is long enough that the inline word diff is not useful. The renderer must show this full block inline, not behind a fold. The old text stays in the document flow with a blue block mark.

- The first list item stays the same.
- The second list item will be removed in the new version.
- The third list item stays the same.

## Section that is removed

This entire section disappears in the new version. The heading and the paragraph are one removed block. The renderer must keep them inline.
