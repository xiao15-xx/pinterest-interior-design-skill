---
name: pinterest-interior-design-skill
description: Search Pinterest through the user's Chrome session for completed interior photography and exceptional CGI, AI, or concept visuals, build bounded review boards, rank references with professional interior-design judgment and visible engagement signals, and download traceable detail-page images. Use for interior reference searches, mood boards, room-view selection, similar-image discovery, and replacement downloads.
---

# Pinterest Interior Design

Use the user's Chrome session and save persistent work under `D:\Codex--A\pinterest-interior-design-search`. Preserve Pin URLs, image URLs, candidate numbers, source bytes, scores, issues, and selection history.

Read only the reference needed for the current phase:

- Before Pinterest work: `references/compliance.md`.
- For browser search, similar images, metadata, or download: `references/chrome-workflow.md`.
- Before ranking or building a board: `references/selection-rubric.md`.
- Only after zero results, browser failure, low preview count, landscape coverage failure, or missing large image: `references/recovery.md`.
- For preference learning data, migration, and examples: `references/preference-learning.md`.

## Workflow

1. Parse project type, room, output use, style, materials, lighting, composition, realism, and requested count. Default final count is 2.
2. Build a compact query from ordered semantic groups: style and room; source and quality; function and core elements; materials and color; lighting and atmosphere. Keep only distinctive terms, remove duplicates, and never include aspect ratios, pixel dimensions, or resolution terms. Round 1 also avoids orientation terms. If a later round is correcting low landscape coverage, controlled `landscape` or `horizontal` composition terms are allowed.
3. Use **REQUIRED SUB-SKILL:** `chrome:control-chrome`.
4. Start every new search task with an isolated browser surface. When the user explicitly asks for incognito, or when prior Pinterest search pages repeatedly reset the browser bridge, first try Incognito Isolation Mode from `references/chrome-workflow.md`: launch a new Chrome incognito window, allow one browser-extension reconnect if the first `openTabs()` call reports the browser is unavailable, verify the Chrome extension can see and claim that exact Pinterest task tab, then use it for discovery. If the incognito tab is still not visible or controllable after that reconnect, record `INCOGNITO_CONTROL_UNAVAILABLE`; do not pretend incognito is active. Otherwise use `browser.tabs.new()` for a normal task-owned tab. Never reuse, claim, or navigate unrelated user pages.
5. Run at most four discovery rounds. Round 1 uses all applicable query groups. Round 2 prefers the best valid Round-1 Pin's visible similar-image feed unless the board fails landscape coverage; then use a landscape-intent keyword query. Round 3 changes function or related elements. Round 4 changes materials, lighting, and style language. Mature preferences may influence only supplemental terms in Rounds 3-4; they never remove project type, room, output use, or the four-round structure. In incognito mode, a round that times out during card extraction poisons that search tab for further extraction; the next discovery round must launch and verify a fresh incognito task tab instead of reclaiming the timed-out tab.
6. Read search pages with the three-tier search-fix path in `references/chrome-workflow.md`: (A) verified incognito control, (B) normal controlled tab with ultra-light search-page reads and direct Pin-detail extraction, then (C) user-confirmed Pin URL rescue only when automation cannot produce traceable Pin/image pairs. Use a timeout circuit breaker in every tier: navigate with the shortest reliable load target, then run one minimal non-DOM status probe (`title`, `url`, visible login/error state when cheap) and one bounded first-screen card read as separate calls. In verified incognito mode, the preferred card read is a single `a[href*="/pin/"] img` extraction capped at 80 anchors and 16 returned cards with a short timeout; it must return only Pin URL, image URL, alt text, and rendered dimensions. Pin-link counts are optional and must not be collected with locator counts or page-wide DOM reads when Pinterest is unstable. Do not combine DOM, visual, and `pageAssets` reads in one search-page step. Do not call full search-page `pageAssets` inventories; reserve `pageAssets` for final Pin detail pages. If Round 1 returns no verified data because the probe times out, reconnect or refresh once and retry the same query with the lightest card read before recording `DOM_READ_TIMEOUT`. Perform at most one short scroll only when the cumulative unique preview pool is below 10. If cumulative landscape coverage is low, do not keep scrolling the same feed; record the issue and move to the next query. Keep extraction, deduplication, dimension checks, and scoring inside Node REPL variables. Emit only compact summaries; never print full DOM, full `pageAssets` inventories, or all recommendations.
7. If Pinterest is visible but card extraction times out, record `DOM_READ_TIMEOUT`, run one short recovery check, then continue with the next automated discovery round using a changed query or seed. If incognito was requested but unavailable, record `INCOGNITO_CONTROL_UNAVAILABLE` before choosing the fallback or stopping. Do not ask for manual Pin URLs, and do not build from screenshots.
8. After each successfully read round, update the cumulative unique preview pool after deduplication, decoding, and basic relevance filtering. If the cumulative pool contains fewer than 10 previews, record `LOW_PREVIEW_COUNT`. If the cumulative pool contains at least 10 previews but fewer than 40% are landscape images accepted by `references/selection-rubric.md`, record `ASPECT_GATE_LOW`. The next round must reference the failed round, change its query or similar-image seed, and record a targeted correction as specified in `references/recovery.md`.
9. Merge by Pin URL, image URL, SHA-256, and perceptual similarity. Build only when 10-16 valid previews remain and the cumulative board passes `references/selection-rubric.md`.
10. Create source and search-attempt metadata. Include `ProjectType` and `OutputUse` when known so preference scope can be recorded as `project_type|room|output_use`; otherwise use `general` and `presentation`. Then run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/candidate_workflow.ps1 `
     -Action Build -InputDir <preview-dir> -OutputRoot 'D:\Codex--A\pinterest-interior-design-search' `
     -Topic <topic> -Style <style> -SearchQuery <round-1-query> `
     -SourceMetadata <candidate.json> -SearchAttemptLog <attempts.json> `
     -ProjectType <project-type> -OutputUse <output-use>
   ```

11. Show the professional-review candidate board once. It should use the magazine-style card layout in `references/selection-rubric.md`: large image tiles, bilingual Chinese/English field labels, short role/source/score/reason text, and no Pin URLs, hashes, or long diagnostics on the board. Rank by `ProfessionalScore`, then eligible `ContextPreferenceScore`, then `DiversityScore`; hard rejections always override popularity or preference.
12. If the user specified a final count, announce it. Otherwise prompt once and use 2 when unchanged.
13. Open only final Pin pages in the task-owned tab. Choose the largest non-preview resource explicitly exposed by `currentSrc`, `srcset`, or `pageAssets`. Download in this order: visible Pinterest download, Chrome native download, then `scripts/controlled_download.ps1` for the already verified URL.
14. Run `SelectLarge` with complete large-image metadata. For 2 or more interior images, require at least one full-space view and complementary roles. The first image cannot be `detail`.
15. If a chosen Pin lacks a usable large image, automatically try one similar-image recovery for that failed slot. Never substitute its preview. Record the original candidate, failure, and replacement.
16. After final selection, write `reviews/batch-review.json`, keep `reviews/round-review.jsonl`, and run `scripts/update_preferences.ps1` when updating the long-term profile is part of the task. Never treat unselected candidates as dislikes.
17. Return only the project path, candidate board when built, final paths, candidate numbers, compact score rationale, low-preview, landscape-coverage, timeout, download, preference status, or replacement rounds. Finalize Chrome once; close the task tab by default, except for login, CAPTCHA, permission, or safety prompts.

## Preference Learning

- Preference scope is `project_type|room|output_use`, for example `villa|master-bathroom|presentation`.
- Effective learning behaviors are final selection, successful large download, moodboard add, quality replacement, and hard rejection. Unselected candidates are ignored.
- A preference scope affects ranking only after at least 3 effective behaviors from at least 2 projects and confidence `>= 0.70`.
- A preference scope may affect supplemental search terms only at confidence `>= 0.80`, and only in Rounds 3-4. It must never remove room type, project type, output use, or core functional intent.
- Candidate ranking uses: `ProfessionalScore * 0.75 + ContextPreferenceScore * 0.20 + DiversityScore * 0.05`.
- Store persistent profile data under `D:\Codex--A\pinterest-interior-design-search\preferences\profile.json`.

## Recovery

- Stop for login, CAPTCHA, permission, or safety prompts.
- Allow one short browser recovery check per failure state; do not loop long operations.
- Treat `DOM_READ_TIMEOUT` as a page-read failure, not as `NO_RESULTS` or `LOW_PREVIEW_COUNT`. It continues to the next automated round without any manual-selection fallback.
- Treat `ASPECT_GATE_LOW` as a landscape-coverage failure. Correct it with a changed seed or controlled landscape-intent query, not by repeated scrolling.
- Four failed discovery rounds stop before `Build`.
- Failed large-image replacement preserves the current valid selection.
