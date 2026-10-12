---
title: "Review Mode Test Fixtures"
date: 2026-10-09
tags:
  - review-mode
  - fixtures
  - testing
---

# Review Mode Test Fixtures

Use these files to test the review diff.

## Steps

1. Copy `before.md` to a scratch path.

   ```bash
   cp Tests/fixtures/review/before.md /tmp/review-test.md
   ```

2. Open the scratch file in FluxMarkdown.

   ```bash
   open -a FluxMarkdown /tmp/review-test.md
   ```

3. Wait for the preview.

4. Replace the scratch file with the new version.

   ```bash
   cp Tests/fixtures/review/after.md /tmp/review-test.md
   ```

5. The preview reloads. The review toolbar appears.

6. Use the toolbar to mark each change as reviewed.

7. Close the preview. The reviewed state stays for the same file path.

## What to check

- The first paragraph shows red struck-through `cookies and` and green `and encrypts it`.
- The second paragraph keeps the link and marks `text` to `words`.
- The second list item marks `changes` to `changed`.
- The removed paragraph shows inline with a red strike-through. No "Before" fold appears.
- The rewritten quote shows the old quote inline with a blue block mark. No "Before" fold appears.
- The unchanged heading, section, and Mermaid diagram show no marks.

## Large block change fixture

Use the `block-change-before.md` and `block-change-after.md` files to test a
large block change. Follow the same steps as above. Change only the file names.

```bash
cp Tests/fixtures/review/block-change-before.md /tmp/review-test.md
open -a FluxMarkdown /tmp/review-test.md
cp Tests/fixtures/review/block-change-after.md /tmp/review-test.md
```

### What to check

- The first paragraph marks one changed word inline.
- The second paragraph shows the full old block inline. A blue block mark
  shows the change. No fold hides the old text.
- The removed list item shows inline with a red strike-through.
- The removed section shows inline with a red strike-through.

## Reset

Delete the scratch file.

```bash
rm -f /tmp/review-test.md
```

The review state is in the web view `localStorage` under the `flux-review:` prefix.
