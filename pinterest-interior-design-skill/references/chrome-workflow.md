# Chrome Workflow

## Search

## Search Failure Resolution Matrix

Use these three solutions in order when Pinterest search pages produce repeated `DOM_READ_TIMEOUT`, search-page screenshot timeout, coordinate-click timeout, or `INCOGNITO_CONTROL_UNAVAILABLE`.

### Solution A: Incognito Extension Permission

- Best when Pinterest's normal logged-in page is too heavy or stale.
- Launch a Chrome incognito window only after the user requests it or repeated bridge resets justify it.
- Verify the exact incognito Pinterest search tab is exposed by the Chrome extension before doing any search work.
- After launching the incognito window, the first extension call may briefly report that the browser is unavailable. Treat this as a transient bridge reset: wait about 2 seconds, reacquire the extension browser once, and repeat only the lightweight `openTabs()` check before deciding.
- If the tab is not visible through `browser.user.openTabs()`, record `INCOGNITO_CONTROL_UNAVAILABLE` and stop incognito testing. The user must enable "Allow in incognito" for the Codex Chrome extension before this solution can pass.
- Do not claim a normal tab and label it incognito.

### Solution B: Controlled Normal Tab With Direct Pin Extraction

- Use when incognito is unavailable but the normal task-owned tab can still navigate and read title/url.
- Avoid search-page page-wide `evaluate`, locator counts, visible-DOM dumps, full-page screenshots, and search-page `pageAssets`.
- Perform one ultra-light card-read attempt only. If it returns traceable `PinUrl + ImageUrl` pairs, continue to Build.
- If search-page reads still reset the bridge, stop discovery rather than looping. Do not use screenshots as candidate sources.
- When a valid Pin URL is already known from the task tab or a previous valid candidate, open the Pin detail page directly and extract large image resources there; detail pages are usually lighter than search pages.

### Solution C: User-Confirmed Pin URL Rescue

- Use only when automated search cannot produce any traceable `PinUrl + ImageUrl` pairs and the user still wants progress in the same task.
- The user may provide 2-4 Pin URLs for direct large-image download, or 10-16 Pin URLs for a candidate board.
- Screenshot-only input is not enough. Every rescued image must still have a Pinterest Pin URL and page-provided media URL.
- Re-run the same professional scoring, source-type labeling, full-space check, large-image rejection, and metadata rules. Mark rescued records with `RecoveryMode=user-confirmed-pin-url`.

1. Name the Chrome session, then create one isolated task surface. Default mode uses one task-owned tab with `browser.tabs.new()`. If the user explicitly requests incognito, or prior Pinterest search-page reads repeatedly reset the bridge, use Incognito Isolation Mode:
   - Launch a new Chrome incognito window to the Pinterest search URL with the local Chrome executable and `--incognito --new-window`.
   - Immediately call `browser.user.openTabs()` only to verify whether that exact Pinterest incognito task tab is exposed to the Chrome extension. If this first lightweight call reports that the browser is unavailable, wait briefly, reacquire the extension browser once, and repeat `openTabs()` before marking the mode unavailable.
   - Claim only that exact task tab with `browser.user.claimTab(tab)` when it is visible. This is the only allowed `openTabs()` / `claimTab()` exception.
   - If the incognito task tab is not visible or claimable, record `INCOGNITO_CONTROL_UNAVAILABLE`, close or ignore the incognito window, and either fall back to `browser.tabs.new()` or stop when the user required incognito-only execution.
   - Never claim unrelated user pages, old Pinterest pages, or normal tabs as a substitute for the incognito task tab.
   Navigate only the task surface to Pinterest and check visible login/error state.
2. Build each query from these ordered groups: (A) style and room type, (B) source and quality, (C) function and core elements, (D) materials and color, and (E) lighting and atmosphere. Keep only the most distinctive phrase from each applicable group, remove repeated meanings, and omit empty groups. Reject aspect-ratio, pixel-dimension, and resolution terms in every round. Round 1 also rejects orientation terms; rounds 2-4 may use controlled `landscape` or `horizontal` terms only when correcting `ASPECT_GATE_LOW` or `LANDSCAPE_COVERAGE_LOW`.
3. Round 1 combines A-B-C-D-E. Round 2 uses the best valid Round-1 Pin's visible similar-image feed and records its Pin URL as `SeedPinUrl`; if the previous issue is landscape coverage, use a landscape-intent keyword query instead. If similar images are unavailable, the fallback query combines A-B-C with shorter synonyms. Round 3 keeps A-B and replaces C with adjacent uses or related spatial elements. Round 4 keeps the room anchor while replacing D-E and, when useful, the style wording in A. Mature preference terms may be added only to Rounds 3-4 after the active scope reaches confidence `>= 0.80`; they must be supplemental and must not replace the room, project type, output use, or core functional intent.
4. Reuse the same task-owned tab or verified incognito task tab for all four rounds and for final Pin detail checks. Do not create one tab per round and do not navigate any unrelated pre-existing user tab.
   - Exception: in verified incognito mode, if a search-page card read times out and resets the browser bridge, treat the current incognito tab as poisoned for extraction. The next discovery round must launch a fresh incognito task tab, verify it through `openTabs()`, and claim only that new tab. Do not reclaim the timed-out search tab for another card read.
5. Read search results with a timeout circuit breaker. Navigate with the shortest reliable target (`commit` or `domcontentloaded`), then run a minimal non-DOM status probe for URL, title, and cheap visible page state. Rough Pin-link count is optional; skip it if it requires locator counts, page-wide DOM evaluation, visible-DOM dumps, or any call that has timed out in the current task. Keep the status probe, card read, and optional scroll as separate browser calls with small result payloads; never combine DOM extraction, visible DOM, screenshots, and `pageAssets` in one search-page step. Do not call full search-page `pageAssets.list()` because Pinterest waterfall pages can stall the Chrome bridge. Reserve `pageAssets` for final Pin detail pages after a candidate is chosen. If Round 1 returns no verified data because the probe times out, reconnect or refresh once and retry the same query with the lightest first-screen card read before recording `DOM_READ_TIMEOUT`. Then read only a small first-screen card set. If more candidates are needed because the cumulative unique preview pool is fewer than 10, perform at most one short scroll and one more small card read.
6. If the cumulative unique preview pool has at least 10 previews but landscape coverage is below 40%, record `ASPECT_GATE_LOW` and navigate to the next discovery query; do not keep scrolling the same waterfall feed.
7. If the status probe or card read times out after the single recovery check, record `DOM_READ_TIMEOUT` and continue to the next automated discovery round with a changed query or seed. Do not keep scrolling, repeat DOM reads, or build from screenshots. If all automated tiers fail and the user explicitly wants continuation, use Solution C rather than pretending automation succeeded.
8. Discover visible Pin cards with bounded DOM evaluation only after the status probe succeeds. Cap first-screen reads to the smallest set that can satisfy the cumulative pool. In verified incognito mode, use one small `a[href*="/pin/"] img` extraction capped at 80 anchors and 16 returned cards with a short timeout; return only normalized Pin URL, image URL, alt text, and rendered dimensions. If one bounded read times out, mark the round with `DOM_READ_TIMEOUT`; do not retry the same heavy expression, and do not reclaim that timed-out incognito tab for the next round. Keep arrays in Node; emit only `{round,status,rawPinCount,validPreviewCount,cumulativeValidPreviewCount,landscapePreviewCount,cumulativeLandscapePreviewCount,eligibleVisualCount,issue,rejections}`.
9. Export only the final 10-16 previews. `/236x/` and `/474x/` are allowed for contact-sheet previews with no minimum dimensions.

## Candidate Metadata

Each candidate record must contain `FileName`, `PinUrl`, `ImageUrl`, `VisualSourceType`, `VisualQualityEvidence`, `SpaceRole`, `SpaceRoleEvidence`, the eight professional score fields, and `FullSpace`. `VisualSourceType` is `photo`, `cgi`, `ai`, or `concept`; synthetic types require at least 75/90. Optional visible metrics are `SaveCount`, `ViewCount`, and `EngagementScore`. `ContextPreferenceScore`, `DiversityScore`, and `FinalScore` are computed during Build.

Each search-attempt record contains `Round`, `Method`, `Query` or `SeedPinUrl`, `RawPinCount`, `ValidPreviewCount`, `EligibleVisualCount`, `RejectionReasons`, `CauseCodes`, `PageStatus`, and `Timestamp`. Add `CumulativeValidPreviewCount`, `LandscapePreviewCount`, and `CumulativeLandscapePreviewCount` whenever cumulative board-gate decisions are made. A round following a low-count, landscape-coverage, or DOM-timeout issue also requires `AddressesRound`, `CorrectionActions`, and `AdjustmentSummary`.

## Large Images

1. Announce an explicit requested count; otherwise prompt once and default to 2.
2. Open only final Pin URLs. Inspect `currentSrc`, `srcset`, and filtered `pageAssets` results without dumping inventories.
3. Reject `/236x/` and `/474x/`. Never construct an `originals` URL; an explicitly listed `736x`, `1200x`, or `originals` resource is valid.
4. Try visible Pinterest download, then Chrome native download. If neither yields a file, run `controlled_download.ps1` only with the already verified HTTPS `i.pinimg.com` URL.
5. Large metadata includes `CandidateNumber`, `FileName`, `ImageUrl`, `PinUrl`, `DownloadMethod`, `DownloadStatus`, optional `FailureCode`, and optional `ReplacementOfCandidateNumber`.
6. If no usable large resource exists, automatically try one similar-image recovery for that slot. Re-score the replacement and preserve its source relationship. Do not use previews to fill failed large-image slots.

## Persistence

- Persist full data to project metadata; keep user-facing output compact.
- Preserve candidate bytes and stable numbers. Never overwrite source bundles.
- Candidate preview files use compact English slugs such as `modern-minimalist-bathroom-preview-01.jpg`; final selections use date-room numbering such as `20260623-bathroom-01.jpg`.
- Write `reviews/round-review.jsonl` from search attempts and `reviews/batch-review.json` from the final candidate/selection state.
- Run `scripts/update_preferences.ps1` only after verified behavior exists. It may update `preferences/profile.json`, but unselected candidates are not negative feedback.
- Finalize Chrome exactly once after browser work. Close the task-owned tab by default; keep it open only for login, CAPTCHA, permission, or safety prompts that require the user.
