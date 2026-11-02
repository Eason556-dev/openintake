# Dashboard nutrient fields and shared checking prompt

## Root cause

The dashboard already targeted valid HealthKit types. The defect was earlier in meal input: nutrient declarations such as `Protein: 32 g` were interpreted as food names and portion weights. History displayed those raw rows, while only the separately parsed energy value reached the frozen HealthKit write plan. A synchronized energy sample did not establish that the protein/fat text had become nutrition samples.

## Repair

- `MealNutritionText` in `TextMeal.swift` recognizes standalone, exact nutrient names/aliases and explicit compatible units. It separates whole-meal totals from food quantities, supports English/Chinese and the existing 39 nutrient identifiers, merges equal bilingual duplicates and rejects conflicting totals or unsupported conversions. Unknown values remain absent; actual zeros are retained only when explicitly confirmed where necessary.
- `OfflineMealParser` passes these totals into `MealReviewState`; they replace corresponding calculated totals once rather than being added again. Existing manual adjustments survive re-parsing. Nutrient-only meals do not require invented food weights.
- The dashboard, Watch snapshot and complications use `DashboardMetric.nutrientID` as a shared mapping. Primary metrics are energy, protein, carbohydrates, total fat, fiber, saturated fat, total sugar, sodium and water. All nine identifiers and canonical units were checked in the installed Xcode 27.2 `HKTypeIdentifiers.h` SDK declarations. These are part of the 39 existing nutrition quantities, not app-only substitutes.
- History separates original text from actual saved samples. Nutrient text is no longer displayed as a food portion. Sodium and other values use their appropriate display units. Missing targets are identified explicitly; they do not hide recorded amounts.

## Existing records

No raw-text totals are silently counted as verified Health data. A legacy record with known nutrient declarations missing from its write plan gets a dashboard/history repair notice. Choose **Complete nutrients & resync**, review the recovered fields, then confirm. The existing event ID and original timestamp are preserved; the existing recoverable edit outbox removes obsolete samples and writes/verifies the replacement. Already saved values win over archived source text. Intentional unknowns remain unknown. Deleted records are not resurrected.

The original automatic projection publication and WatchConnectivity pipeline remain in use: phone persistence publishes the new snapshot, and Watch reception updates the cache and reloads complication timelines. Metadata is not assumed to arrive through HealthKit itself.

## Supplied share prompt

`App/ExternalInformationGuide.swift` now shares the exact user-supplied **OpenIntake — Universal Nutrition Logging Assistant** text (trailing newline excluded). No instructions in that payload are executed by OpenIntake and no external model/network integration was added.

The supplied text says 38 fields but actually lists 39. It also requests numeric zero placeholders for unknown values. The payload remains verbatim; the UI discloses these two details. Full-schema imported zeros require review: confirm an actual zero or mark it unknown, with a bulk unknown action. Unknown decisions persist in the product snapshot and are excluded from future legacy-repair suggestions. Full external schema values are conservatively tagged as user-supplied estimates, not verified food measurements. Known manual values remain distinguishable.

## Validation

- 219 core tests pass (0 failures), including the pre-existing supplement, retry, undo and Watch replay suite.
- New regressions cover a synthetic nine-field meal through parsing, write plans and every phone/Watch dashboard metric; all 39 identifiers; bilingual units; duplicate/conflicting summaries; unsupported forms; goal-independent numbers; reviewed legacy recovery preserving ID/date; authorization refusal, partial failure/retry, duplicate prevention and deletion; full-schema placeholders and persisted unknowns.
- Unsigned iOS Simulator, generic iPhone device and independent watchOS Simulator builds pass.
- English/Chinese localization audit and public-file privacy scan pass.

Tests use synthetic records, not the user's lunch or personal health data. Fake-backend/JSON projection evidence does not establish physical iPhone HealthKit acceptance or real Watch background-delivery timing. After installing, repair the existing meal once and verify its samples in Apple Health plus the paired Watch/complication refresh. No physical-device intake was created by these checks.
