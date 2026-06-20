---
name: pinterest-interior-design-skill
description: Use when searching Pinterest in Chrome for visual references, downloading a small curated image set, reviewing numbered candidates, selecting design images, or replacing a previous Pinterest selection by candidate number.
---

# Pinterest Skill

## Core Principle

Use the user's Chrome session for a bounded, visible Pinterest search. Preserve original candidate files, source metadata, and a numbered review board so final selections remain reversible.

Read `references/compliance.md` before collecting or downloading images. Read `references/chrome-workflow.md` before controlling Chrome. For quality-sensitive selection, read `references/selection-rubric.md`.

## Defaults

- Use the user-provided output root. Otherwise use `<cwd>/pinterest-image-search/preview-images`.
- Save 2 final images when no count is specified.
- Collect 8-16 visible candidates, with 16 as the hard maximum.
- Name projects `YYYY-MM-DD_topic_style` in Asia/Shanghai time; append `_02`, `_03`, and so on when needed.
- Preserve each source file's bytes and `.jpg`, `.jpeg`, `.png`, or `.webp` extension.
- Auto-select and save the best results. Do not pause unless the user explicitly asks to preview or choose first.

## Workflow

1. Parse the brief into topic, style, use, composition, realism, and requested count.
2. Generate a compact query plan:

   ```bash
   python scripts/search_planner.py "东方 新中式 书房 室内设计" --lang both --count 12 --interior --format json
   ```

3. Use **REQUIRED SUB-SKILL:** `chrome:control-chrome` when Chrome or the user's Pinterest session is required. Run one focused Pinterest search, then refine once only if visible results clearly miss the brief.
4. Inspect visible results and retain a diverse set of 8-16 candidates. Do not automate infinite scrolling. Prefer the largest page-provided image asset; never invent an `originals` URL.
5. Save the bounded assets to a temporary input directory without transcoding. Create source metadata as described in `references/chrome-workflow.md`.
6. Build the persistent review project:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/candidate_workflow.ps1 `
     -Action Build -InputDir <asset-dir> -OutputRoot <output-root> `
     -Topic <topic> -Style <style> -SearchQuery <query> `
     -SourceMetadata <source-metadata.json>
   ```

7. Rank candidates with `references/selection-rubric.md`. For an interior set of 2 or more images, include at least one candidate whose `FullSpace` value is true.
8. Save current selections by stable candidate number:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/candidate_workflow.ps1 `
     -Action Select -ProjectDir <project-dir> -CandidateNumber 6,13 `
     -Role full-room,alternate-view -Interior
   ```

9. Return the project path, final file paths, selected candidate numbers, and `preview/contact-sheet.jpg`. Preserve the project for later replacement.
10. If the user says to replace a slot with another candidate, rerun `Select` with the complete desired selection. Never rebuild or delete the candidate set.
11. Finalize Chrome exactly as required by `chrome:control-chrome` after all browser work is complete.

## Project Contract

```text
YYYY-MM-DD_topic_style/
|-- candidates/             # unchanged candidate bytes
|-- selected/               # current final selection only
|-- preview/contact-sheet.jpg
|-- candidates.csv
|-- manifest.json           # source of truth and selection history
`-- README.md
```

`Build` prints the new project directory. `Select` prints the current final files. `manifest.json` records hashes, sources, scores, current selections, and every selection operation.

## Failure Handling

- If Pinterest requires login, keep the tab for handoff and ask the user to log in. Do not switch sites to bypass it.
- If browser control fails, follow the Chrome skill's required troubleshooting documentation before retrying.
- If a WebP thumbnail cannot be decoded, keep the original untouched and use an available FFmpeg JPEG preview; otherwise render a labeled placeholder in the contact sheet.
- If fewer than 8 suitable images are visible, save the suitable set rather than lowering the quality bar or scrolling indefinitely.
