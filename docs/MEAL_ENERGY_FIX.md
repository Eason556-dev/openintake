# Meal Energy input repair

The Energy HealthKit type already existed. The meal screen hid it inside a per-100 nutrient menu and had no first-class whole-meal Energy input. The text pipeline recognized food quantities but did not extract explicit kcal/kJ annotations. Those annotations could remain in food names and prevent offline matching.

Changes:

- `App/MealEditor.swift`: visible **Meal energy total** field in kcal, a direct per-food Energy action, dimension-safe nutrient sheet defaults, and explicit bilingual input examples.
- `Sources/IntakeCore/OfflineFood.swift`: extract explicit kcal/kJ/Calories/千卡/大卡/卡路里/千焦 values. Per-food energy replaces that food's reference energy and is normalized using its explicit weight/volume. A separate whole-meal energy annotation becomes one manual total override. Ambiguous multiple totals or per-100 label statements are not silently treated as whole-meal totals.
- `Sources/IntakeCore/MealReview.swift`: support confirmed Energy-only records without inventing weights. Invalid weights still block; per-100 nutrient profiles still need a valid quantity. Changed source text clears a previous parsed energy value, while a separately entered manual override is retained. No acceptance checkbox is required.
- `Sources/IntakeCore/NutritionRegistry.swift`: correct recorded-item coverage for energy-only records.
- `Sources/IntakeCore/TextMeal.swift`: share the existing segment tokenizer rather than introduce a duplicate tokenizer.
- English/Chinese resources and regressions in `Tests/IntakeCoreTests/OfflineFoodTests.swift`.

Examples:

- `Lunch 650 kcal` or `午餐650大卡`: whole-meal energy of 650 kcal; weight remains unknown.
- `Lunch 2719.6 kJ`: 650 kcal after dimensional conversion.
- `米饭200g 300kcal，鸡肉150g 250kcal，柠檬茶500mL 180kcal`: three items and 730 kcal, without adding the rice reference energy a second time.
- `米饭200g，能量650kcal`: 650 kcal is the whole-meal total, overriding the calculated energy once.
- `每100克130kcal`: use the per-100 nutrient form; this is not assumed to be actual meal energy.

Saving continues through the original local outbox, per-type HealthKit permission checks and post-save sample verification. Unknown nutrients are absent. Permission failure retains a pending local record. Stable identities/retry/undo behavior is regression-tested with a fake backend; real iPhone verification remains necessary.

Validation: 207 core tests pass, including 8 new energy regressions covering direct input, bilingual text, kcal/kJ, per-food aggregation, total overrides, missing/invalid weights, stale text, authorization refusal, retry, duplicate protection and undo. Unsigned iOS Simulator and generic iPhone builds pass. The simulator UI audit uses `--meal-review-ui-audit --meal-energy-ui-audit`; it creates no intake record.
