# Pinterest Compliance

Read before Pinterest collection or download.

- Use Pinterest only. Default to the user's visible authenticated Chrome session. When the user explicitly requests incognito, use an isolated incognito Chrome window only if the Chrome extension can control that exact task tab; stop for login, CAPTCHA, or missing extension access instead of bypassing authentication.
- Retain at most 16 primary candidates; do not infinite-scroll, enumerate accounts or boards, scrape hidden internals, or mass-download.
- Do not bypass login, CAPTCHA, rate limits, robots controls, paywalls, or permissions.
- Collect only page-visible Pin links, visible metadata, and page-provided media needed for the user's reference task.
- If automated browser control fails, user-confirmed Pin URLs are allowed only as a bounded rescue path; do not accept screenshots, copied image pixels, non-Pinterest URLs, hidden page state, or guessed media URLs as sources.
- Similar-image recovery is bounded to one attempt per failed final slot.
- Treat images as traceable design references, not owned or licensed assets. Keep source metadata and watermarks intact.
- Never expose cookies, tokens, local storage, credentials, or unrelated personal data.
