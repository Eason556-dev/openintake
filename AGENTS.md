# Repository instructions

- Preserve offline functionality, optional AI, no accounts and no mandatory network dependencies.
- Never equate a scan with ingestion; never convert unknown nutrient values to zero.
- Keep medications separate from nutrition. Verify Apple API claims against official docs and SDKs.
- Keep calculation and data invariants in Sources/IntakeCore; app adapters in App.
- Run swift test for core changes and unsigned xcodebuild for app changes.
- Regenerate OpenIntake.xcodeproj using scripts/generate_project.py after adding/removing Swift files.
- Do not commit personal health data, signing profiles, certificates or API keys.

- Every new intake feature must route supported values through the shared HealthKit outbox, check each write permission and verify saved samples. Local totals or a completed authorization request are not proof of HealthKit synchronization. Keep failure/retry/undo tests, and explicitly distinguish mock/simulator evidence from real-device acceptance.
