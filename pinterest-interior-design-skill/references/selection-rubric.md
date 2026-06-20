# Pinterest Selection Rubric

## Hard Rejections

Reject a candidate when any of these are obvious:

- unrelated subject or style;
- collage, screenshot, poster, or text-led layout instead of a photograph;
- prominent watermark or branding over the subject;
- severe crop that defeats a requested full-space view;
- duplicate or near-duplicate of a stronger candidate;
- low clarity, broken asset, implausible geometry, or conspicuous AI artifacts;
- visually cluttered composition when the brief asks for calm or complete spatial reading.

## Scores

Score each retained candidate from 0-10:

| Field | Meaning |
|---|---|
| `StyleMatch` | Matches topic, geography, era, materials, and mood |
| `Realism` | Looks like a credible photograph or professional render |
| `Clarity` | Useful pixel dimensions, focus, exposure, and legibility |
| `CleanComposition` | Organized framing with limited visual noise |
| `FullSpace` | Boolean: room boundaries and principal furnishings read as one space |

Rank by `StyleMatch` first, then `Realism`, `Clarity`, and `CleanComposition`. Do not let a high aesthetic score override a hard rejection.

## Interior Coverage

For 2 or more final interior images:

- include at least one `FullSpace=true` wide or complete-room view;
- use the other slot for a complementary angle, material detail, or alternate atmosphere;
- avoid two near-identical views;
- prefer a clean full-space view over a more dramatic but confusing one.

## Selection Roles

Use short semantic role names in final filenames:

- `full-room`
- `alternate-view`
- `detail`
- `material-detail`
- `daylight-view`

When replacing a selection, keep slot order stable unless the user explicitly changes it.
