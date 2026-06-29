# Selection Rubric

## Hard Rejections

Reject non-room subjects, wrong room types, collages, severe crops, unusable sources, paranormal or disturbing content, distorted people, strange unrelated objects, illustrations, physical or staged models, mockups, ordinary renders, cheap CGI, and synthetic images with obvious generation errors. Accept completed-interior photography plus exceptional `cgi`, `ai`, or `concept` visuals only when their professional score is at least 75/90 and their source type is explicit. Text or logos are allowed unless they block spatial evaluation.

## Board Gate

- Retain 10-16 unique previews from the cumulative search pool.
- At least 40%, rounded up, must be landscape images within the existing 25% tolerance around 3:2, 4:3, or 16:9. Apply this to the cumulative pool after collection, never in search terms.
- Reject perceptual near-duplicates and false `FullSpace` labels.
- Use the professional-review candidate board by default, not the old contact-sheet grid. The board is a 16:9 landscape image, normally 2560x1440, with a clean 5-column by 2-row card layout for 10 candidates. Each card shows the full preview image without cropping, then bilingual Chinese/English compact fields (`角色 Role`, `来源 Source`, `评分 Score`, `理由 Reason`). Keep Pin URLs, hashes, long reasons, and diagnostics in metadata, not on the board.

## Professional Score: 0-90

| Field | Maximum |
|---|---:|
| `StyleScore` | 22 |
| `FunctionScaleScore` | 12 |
| `CompositionScore` | 18 |
| `SubjectOccupancyScore` | 10 |
| `MaterialDetailScore` | 10 |
| `LightingScore` | 7 |
| `ColorStylingScore` | 7 |
| `ReferenceValueScore` | 4 |

`SubjectOccupancyScore` measures whether the intended interior is the clear visual subject, occupies a useful share of the frame, and keeps its core furniture and interfaces readable without excessive blank margins or unrelated foreground objects. Require concrete visual-quality evidence and a `SpaceRole` of `full-space`, `alternate-view`, or `detail`. Professional score is the field sum; zero-filled scoring is invalid.

## Space Role

- `full-space`: the main room relationship is readable, including the core furniture or fixtures, main enclosing surfaces, scale, circulation, and subject occupancy. It should normally score at least `CompositionScore >= 14`, `SubjectOccupancyScore >= 7`, and `FunctionScaleScore >= 8`.
- `alternate-view`: a useful supporting angle that expands understanding of the same room but does not carry the full spatial story alone.
- `detail`: a material, fixture, vignette, or partial view. It can support a board but cannot be the primary final image for an interior two-image selection.
- `FullSpace` must agree with `SpaceRole=full-space`, and `SpaceRoleEvidence` should state why the role is justified.

## Engagement Score: 0-10

Read public saves/views only for the professional top 4-6. Within the same batch, use percentile ranks: saves 60%, views 40%. Enable a metric only when at least half the shortlist exposes it. Use the batch median for missing values. Engagement cannot override a hard rejection.

## Final Set

Final score is `ProfessionalScore * 0.75 + ContextPreferenceScore * 0.20 + DiversityScore * 0.05`. `ContextPreferenceScore` is zero until its scope is active under `references/preference-learning.md`; `DiversityScore` prevents the final set from becoming visually repetitive. Prefer complementary roles and, for 2 or more images, at least one `full-space`; the first image cannot be `detail`. Recheck downloaded large images; fall through to the next ranked candidate if detail quality invalidates the preview judgment.
