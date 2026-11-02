# Offline nutrition redesign — implementation and acceptance notes

## Audit findings

The previous manual meal editor used `TextMealValidation.fallback` to retain names and explicit g/mL quantities. It did **not** have a food-composition database or calculate nutrition from those names. Its per-100-unit editor was reusable, but rejected database origins and known zero values. Its text-change handler could regenerate draft rows while the user typed; that behavior is removed in favor of the explicit Organize action. The separate acceptance checkbox had already been removed and is not reintroduced.

Existing components retained: Product/MealPortion frozen snapshots, protected atomic JSON persistence, the shared HealthKit outbox, per-type authorization, exact app-owned sample verification, stable sync identifiers/versions, retry/undo/restore, automatic Watch transport, supplement ingredient hierarchy and mapping, hydration, reminders, widgets and Shortcuts.

Previously there was no meal-edit replacement transaction. A replacement can remove nutrient types, so deleting only the new nutrient list would leave obsolete samples in HealthKit. Replacement now persists the old plan before any external operation; retries delete the union of old and new types, then write/verify the new values under the same event identity. This is recoverable replacement, not an atomic transaction spanning HealthKit and local storage. During a failure Health may temporarily contain an incomplete replacement; the event stays pending and is never reported as synchronized.

## Architecture

`OfflineMealParser → FoodReference → MealCalculation → MealReviewState → Product/IntakeEvent → EventSync → HealthWriter`

- Core lookup/calculation/validation lives in `Sources/IntakeCore`.
- `FoodReference` opens a read-only SQLite connection per bounded lookup. FTS5 indexes English names and curated multilingual aliases. No full-dataset deserialization or runtime networking.
- Exact, unique aliases can resolve automatically. Generic beef deliberately has several raw/cooked candidates. Unrecognized names remain intact with unknown nutrition. The review provides food search/selection and manual entry; it never silently substitutes an unrelated food.
- Text supports explicit g/kg/mL/L and oz quantities; English `and` and existing Chinese/comma/list separators split foods. This is a limited grammar, not general natural-language understanding. Household units are selected in structured entry and require a source-specific gram weight. Volume never becomes mass through a generic density assumption.
- `MealPortion` retains source food ID, frozen nutrients, local-only reference values and source/version notes. Original text, meal type, optional name and timestamp are kept separately. Photographs remain temporary visual references and do not change weights.
- Calculation scales each available nutrient independently. Missing fields are absent; explicit database/label/manual zero is retained. Historical AI zero estimates remain conservatively rejected. Per-nutrient known-item counts expose partial totals.
- Overrides are stored separately from the ingredient calculation, use manual provenance and survive quantity changes. Restore calculated value is an explicit action. Per-item edits are marked manual.
- Parent nutrient checks reject sugar/fiber exceeding carbohydrates or fatty-acid fractions exceeding total fat (with small rounding tolerance). A broad energy/macronutrient discrepancy prompts review without replacing source values. This check is not proof of food accuracy.
- Reusable meals are ordinary confirmed products, exposed through the existing iOS/Watch catalog. Watch uses the same phone-side calculator and durable outbox instead of a second nutrition writer or a second reference database. Stable Watch request IDs prevent replay from becoming another intake.

## Food source and licensing

Bundled: **7,793 USDA FoodData Central SR Legacy foods, April 2018 archive, published April 2019**. This is a versioned historical reference, not a current branded-food catalog or Canadian product-label database.

USDA states its data are public domain under [CC0 1.0](https://fdc.nal.usda.gov/api-guide/). Citation: U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, 2019. fdc.nal.usda.gov.

[Official bulk downloads](https://fdc.nal.usda.gov/download-datasets/). Rebuild with:

```sh
python3 scripts/import_food_reference.py /path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip
```

No API key is used. The importer verifies the reviewed archive SHA-256 before replacing data. `food-reference-manifest.json` records the archive hash, source, version and explicit source nutrient-ID mapping. Chinese aliases identify foods only; no nutrient profile is hardcoded for a recipe or commercial product. Most database descriptions and serving names are English. Chinese alias coverage is intentionally small; English search covers the full bundled reference.

Limitations: generic foods vary; preparation, edible weight and variety must be reviewed. Cooked and raw entries are distinct; there is no guessed cooking-yield factor. Branded drinks may require manual per-100-mL label values. Bone/container mass is not corrected automatically. Household conversions are specific to the selected USDA entry. Many source foods lack some nutrients. This database does not provide complete coverage of all 39 metrics for every food.

RAE, DFE, food moisture and added sugars, where provided, are retained as separate local-only values. RAE/DFE are not treated as plain vitamin mass; food moisture is not drinking water; added sugars are not total sugar. Vitamin A RAE is not imported into the HealthKit vitamin A field using an unreviewed equivalence rule.

## HealthKit coverage and safety

All **39 existing targeted nutrition quantities** are declared in the installed Xcode 27.2 HealthKit SDK. The adapter checks runtime type availability, unit compatibility and write permissions; declarations are not authorization. All 39 remain available for appropriate manual/label values, while the USDA importer supplies only explicitly compatible source fields.

Canonical units: grams for mass, milliliters for water, kilocalories for energy. Display units can be mg or mcg without changing canonical values. 130 dietary Calories are 130 kcal. Added sugars has **no dedicated writable HealthKit type** in the inspected SDK and remains app-only.

Apple references: [nutrition types](https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers), [saving data](https://developer.apple.com/documentation/healthkit/saving-data-to-healthkit). SDK audit: `HealthKit.framework/Headers/HKTypeIdentifiers.h` in the installed iPhoneOS SDK; runtime non-writing audit available with debug `--healthkit-catalog-audit`.

Events are persisted before HealthKit access. Writes carry stable per-event/per-nutrient sync IDs, monotonic versions, event/product IDs, origin, food references and nutrient coverage. The adapter queries exact app-owned samples and validates values/timestamps before reporting success. Verified sample UUIDs and verification time are persisted locally. Edits keep the timestamp and event ID, retain prior product versions and remove obsolete types. Deletion only targets the app's exact event identifiers. Failure remains pending and retryable. There are no new reads of unrelated Apple Health data.

## Native UI

Nutrition tab: energy consumed/target/remaining, adaptive three-macro rings, fiber/limit/water progress, pending-sync status and reference-estimate labeling. No default medical targets are invented; targets remain user settings. Limit bars stay neutral and turn cautionary over the limit rather than rewarding higher consumption.

Secondary nutrient screen: all 39 quantities grouped by category, correct units, known/recorded contribution counts and daily/7-day/30-day Swift Charts. Values are this app's recorded known portion, not complete all-source Health totals. Gaps are not zeros. Existing hydration/settings tabs remain, with history/editing and source attribution accessible through navigation.

Watch focuses on energy, protein, carbohydrate, fat, hydration and configured quick entries. Existing complications remain native, and new metrics travel in the existing snapshot. Saved meals use the existing catalog and offline queue. Phone and Watch metadata are transported explicitly; no assumption is made that HealthKit transports meal metadata.

## Validation and device acceptance

See the accompanying final task report for executed test/build results. Automated tests exercise the real bundled reference, English/Chinese parsing, ambiguity, raw/cooked separation, volume retention, unit conversion, scaling, partial totals/known zero, manual overrides, all 39 outbox quantities, edit permission failure/recovery/deletion and reusable Watch meals. Existing supplement, sync, reminder and Watch replay regressions remain in the suite.

On an iPhone:

1. Enter `200g cooked white rice and 150g cooked beef`. Rice resolves; choose the actual beef preparation. Check weights and source IDs. No AI/network is needed.
2. Try `200克米饭，150克牛肉`; verify the ambiguous beef selection. Try a branded 500 mL tea; it must stay a separate item with unknown nutrition until label values are supplied.
3. Adjust a nutrient total, change a portion, confirm that the override remains, then explicitly restore the calculated value.
4. Record and inspect Sync Center, then the exact record in Apple Health. Permission refusal must leave a pending local event, not a success message.
5. Edit a synced meal, removing a nutrient. Verify the obsolete Health sample disappears and the replacement appears once. Retry after interruption. Undo and restore the event.
6. Save a reusable meal; on Watch log it once while disconnected, reconnect and verify one request produces one event and the exact quantity once. Check the new macro values/targets on different Watch sizes.
7. Check English/Chinese, large text, VoiceOver, light/dark appearance and small phone/Watch layouts.

Simulator unit/type checks and fake-backend tests do not prove real-device HealthKit authorization, persistence, background delivery or Watch connectivity. Those require device acceptance.
