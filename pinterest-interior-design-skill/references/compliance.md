# Pinterest Compliance Notes

Read this reference before automating Pinterest collection, downloading, or API access.

## Allowed Direction

- Generate focused Pinterest search URLs and visual query strategies.
- Use the user's visible, authenticated Chrome session when requested.
- Collect a small, bounded set of relevant page-provided assets for the user's design-reference task.
- Preserve visible Pin and image source URLs, asset IDs, and attribution when available.
- Use official Pinterest APIs only with user-provided authorization and currently documented scopes.

## Limits

- Collect at most 16 visible candidates per project.
- Use one focused search and at most one meaningful refinement.
- Do not automate infinite scrolling, scrape page internals, enumerate accounts or boards, or mass-download images.
- Do not bypass login, CAPTCHA, rate limits, robots controls, paywalls, or access restrictions.
- Do not remove watermarks or imply that reference images are owned or licensed assets.
- Do not fabricate creator, Pin, or source information when it is not visible.

## Output Use

Treat saved images as visual references unless the user establishes appropriate reuse rights. Keep `manifest.json` and `candidates.csv` with the project so sources and selection history remain traceable.

## Official Sources To Recheck For API Work

- https://developers.pinterest.com/
- https://policy.pinterest.com/en/developer-guidelines
- https://policy.pinterest.com/en/terms-of-service
