# Nutrition redesign — validation report

Validated locally on 2026-11-01 with Xcode 27.2 (27B52).

## Results

- `swift test`: **199 tests passed, 0 failures**. The previous suite had 174 tests; 25 new offline nutrition/edit/Watch reuse regressions are included.
- Unsigned iOS Simulator app/widgets build: passed.
- Unsigned generic iPhone device build, including embedded Watch targets: passed.
- Independent watchOS Simulator app/complications build: passed.
- iOS 27.2 simulator non-writing HealthKit audit: **39/39 types available and unit-compatible**. Constructed audit samples were not saved.
- English meal review and nutrition dashboard launched and visually inspected in Simulator. This is not real-device HealthKit acceptance.
- Localization audit: 570 literal UI-key uses, 761 English table entries, no missing-key/placeholder findings.
- Public-file privacy scan: no findings; quoted Xcode/JSON credential keys are now checked too. No accounts, API keys, signing profiles or health logs were added.
- Bundled SQLite integrity check: `ok`; 7,793 foods and 7,793 indexed search rows. 36 explicitly mapped compatible USDA nutrient IDs; the 39-type manual/label HealthKit capability is separate from database coverage.
- All 76 pre-existing Xcode project-setting differences were retained. The original schemes and unrelated pre-existing CONTRIBUTING edit were preserved.

## New test coverage

English/Chinese multi-food entry; raw/cooked ambiguity; unknown foods; explicit g/kg/oz and mL/L retention; source-specific household portions; duplicate serving labels; real USDA scaling; known zero versus missing; partial aggregation; retained overrides and refresh; negative/wrong-unit rejection; energy/parent checks; source-only RAE/DFE/moisture isolation; caffeine versus trans-fat source-ID regression; all 39 quantities through the shared mocked outbox; interrupted replacement retry; edit permission refusal before deletion; deletion after editing to unknown-only; frozen-plan validation; renamed reference invalidation; reusable Watch catalog resolution. Existing supplement hierarchy, bilingual OCR, outbox retry/undo/restore, notification and Watch request-replay regressions also passed.

## Main modified files

Core and database:

- `Sources/IntakeCore/OfflineFood.swift` (new)
- `Sources/IntakeCore/NutritionRegistry.swift` (new)
- `Sources/IntakeCore/Resources/FoodReference.sqlite` (new)
- `Sources/CSQLite/module.modulemap`, `Sources/CSQLite/shim.h` (new)
- `Sources/IntakeCore/DailyIntake.swift`
- `Sources/IntakeCore/MealReview.swift`
- `Sources/IntakeCore/Models.swift`
- `Sources/IntakeCore/LibraryRepository.swift`
- `Sources/IntakeCore/EventSync.swift`
- `Sources/IntakeCore/QuickIntake.swift`
- `Sources/IntakeCore/DashboardBuilder.swift`
- `Shared/DashboardSnapshot.swift`

Adapters and UI:

- `App/MealEditor.swift`
- `App/DashboardViews.swift`
- `App/NutritionDetails.swift` (new)
- `App/RecordHistory.swift`
- `App/IntakeStore.swift`
- `App/HealthWriter.swift`
- `App/OpenIntakeApp.swift`
- `WatchApp/OpenIntakeWatch.swift`
- `WatchWidgets/OpenIntakeComplications.swift`
- English/Chinese `Shared/Resources/*/Localizable.strings`

Build, tests and documentation:

- `Package.swift`
- `scripts/generate_project.py`, generated Xcode project source/resource entries
- `scripts/import_food_reference.py` (new)
- `scripts/check_public_files.py`
- `Tests/IntakeCoreTests/OfflineFoodTests.swift` (new)
- `docs/food-reference-manifest.json` (new)
- `docs/OFFLINE_NUTRITION_REDESIGN.md` (new)
- `README.md`, `README.zh-CN.md`, this report

## Remaining limits and device work

The parser is a deterministic limited grammar, not universal language understanding. Chinese aliases cover a small reviewed subset; other references can be searched in English. Reference descriptions/serving names remain source text. Restaurant recipes and branded drinks are not guessed: choose an appropriate reference or enter label/manual values. No inferred cooking yield or generic liquid density is applied. Source profiles may be incomplete. Added sugars has no dedicated HealthKit type; RAE/DFE/moisture are retained locally and not forced into incompatible writes.

Watch remains a lightweight companion: it queues configured products/meals offline and the iPhone performs authoritative calculation and HealthKit writes. It does not carry the entire food database or provide standalone meal search. Dashboard/trends represent OpenIntake records, not every source in Apple Health. User-selected targets are not prescribed defaults.

Real iPhone/Watch acceptance is still required for actual permission denial/re-enabling, saved sample verification, interrupted edits, background Watch delivery/replay and different Watch layouts. No physical-device intake was created during this task. Follow the concrete acceptance steps in `OFFLINE_NUTRITION_REDESIGN.md`.
