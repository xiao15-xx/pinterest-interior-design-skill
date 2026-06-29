# Preference Learning

## Purpose

Learn by project context, not globally. The scope key is:

```text
project_type|room|output_use
```

Examples:

- `villa|living-room|presentation`
- `residential|bathroom|moodboard`
- `hotel|bedroom|ai-reference`

## Valid Behavior

Only these events can update preferences:

- `final_selection`
- `large_download_success`
- `moodboard_add`
- `quality_replacement`
- `hard_rejection`

Unselected candidates are ignored. They are not negative feedback.

## Activation

- Record all valid behavior immediately.
- Ranking influence starts only after at least 3 effective behaviors from at least 2 projects and confidence `>= 0.70`.
- Supplemental search-term influence starts only after confidence `>= 0.80`.
- Search-term influence is limited to Rounds 3-4 and cannot remove room type, project type, output use, or core functional intent.

## Score Formula

```text
FinalScore =
ProfessionalScore * 0.75
+ ContextPreferenceScore * 0.20
+ DiversityScore * 0.05
```

`ProfessionalScore` remains the main design-quality signal. Preference helps choose among already-good candidates; it cannot rescue hard rejections.

## Profile Example

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-06-23T00:00:00.0000000Z",
  "rules": {
    "minimumEffectiveBehaviors": 3,
    "minimumProjects": 2,
    "rankingConfidenceThreshold": 0.7,
    "queryConfidenceThreshold": 0.8,
    "unselectedIsNegative": false
  },
  "scopes": {
    "villa|living-room|presentation": {
      "scope": "villa|living-room|presentation",
      "effectiveBehaviorCount": 5,
      "projectCount": 2,
      "confidence": 0.82,
      "activeForRanking": true,
      "mayAffectSearchTerms": true,
      "mayAffectRoundExpansion": true,
      "weights": {
        "full_space": 0.66,
        "stone_feature_wall": 0.18,
        "warm_neutral": 0.12
      }
    }
  }
}
```

## Round Review Example

```jsonl
{"projectName":"2026-06-23_bathroom_modern","scope":"residential|bathroom|presentation","round":1,"method":"keyword","rawPinCount":34,"validPreviewCount":23,"cumulativeValidPreviewCount":23,"landscapePreviewCount":0,"cumulativeLandscapePreviewCount":0,"causeCodes":["ASPECT_GATE_LOW"],"correctionActions":[],"pageStatus":"ok","timestamp":"2026-06-23T00:00:00Z"}
```

## Batch Review Example

```json
{
  "projectName": "2026-06-23_bathroom_modern",
  "scope": "residential|bathroom|presentation",
  "boardStyle": "professional-review",
  "candidateCount": 10,
  "effectiveBehaviors": [
    {
      "type": "final_selection",
      "candidateNumber": 4,
      "role": "full-space",
      "outputFile": "20260623-bathroom-01.jpg"
    },
    {
      "type": "large_download_success",
      "candidateNumber": 4,
      "outputFile": "20260623-bathroom-01.jpg"
    }
  ],
  "hardRejections": []
}
```

## Examples

Living-room presentation:

- Scope: `villa|living-room|presentation`
- Likely learned positives: `full_space`, `wide composition`, `stone feature wall`, `warm neutral`, `low modular sofa`
- Use: ranking first; after high confidence, Round 3-4 may add supplemental terms such as `warm neutral stone wall`.

Primary-bathroom presentation:

- Scope: `residential|bathroom|presentation`
- Likely learned positives: `full_space`, `stone vanity`, `walk in shower`, `freestanding tub`, `soft indirect lighting`
- Use: ranking first; after high confidence, Round 3-4 may add supplemental terms such as `stone vanity soft indirect lighting`.

## Migration

Old projects without `reviews/batch-review.json` remain readable. They do not update preferences until a new selection produces effective behavior. Old manifests without `schemaVersion >= 5` should be treated as preference-neutral and `ContextPreferenceScore = 0`.
