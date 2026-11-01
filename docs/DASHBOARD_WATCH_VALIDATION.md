# 0.6.0 dashboard, language and Watch validation

Validation date: 2026-10-22. Build 14. This is a development build, not a release or device acceptance claim.

## Changes

- Nutrition, Hydration and Settings tabs. History, health synchronization, permissions, reminders, goals and language controls live in Settings.
- Native tab/navigation presentation and availability-gated Liquid Glass action buttons on supported iOS versions; material fallback on older versions.
- English and Simplified Chinese UI resources. System language is the default; explicit preference is stored locally. Language changes do not recreate the ledger, rewrite ingredient IDs, or change quantities. Product names and OCR evidence remain original; some underlying diagnostic messages still retain their source language.
- Watch companion shows water, energy, protein, sugar and sodium, with current values, optional personal goals and estimate markers. Sugar/sodium are limits, not encouragement to consume more.
- Five WidgetKit complications support accessoryCircular, accessoryRectangular, accessoryInline and accessoryCorner. Available positions depend on the watch face. No legacy ClockKit claim.
- Phone sends a minimal daily snapshot through WatchConnectivity. It contains totals, targets, update time, language and pending count, not product names, photos, OCR or full intake history. Watch app and extension share a local App Group cache. This is a projection, not another HealthKit writer.
- Unknown values stay unknown; undo excludes amounts; pending HealthKit writes remain visible as pending. Midnight or timezone mismatch hides stale amounts. Displayed totals include local records and are not proof of HealthKit synchronization.

## Fixes completed after the interrupted session

- Apply language environment above the root view so presented UI inherits it.
- New ingredient editors default to interface language instead of forced Chinese (an existing explicit ingredient preference is retained).
- Interpolate localized values once, preserving literal braces in user-supplied names.
- Add the existing icon to the Watch target and project generator.
- Replace an unavailable sodium symbol found during simulator screenshot inspection.
- Add eight dashboard/localization tests; existing supplement and meal parsers remain unchanged.

## Evidence

- `swift test`: 149 tests, zero failures. Includes prior semantic parsing, meal confirmation, outbox retry/verification/undo tests, plus new totals/unit conversion, unknown vs zero, undo/restore, day rollover/DST/timezone, invalid goals, snapshot and localization tests.
- Generic iOS Debug unsigned build: successful, including iOS widget, embedded Watch app and Watch complication targets.
- Generic iOS Debug build using ignored local signing configuration: successful. No provisioning/account changes or publication requested.
- Generic iOS Simulator Debug build: successful. Installed and launched on iPhone simulator; English Nutrition screen renders, no launch white screen.
- Localization resource key/placeholder parity checked. Public-file heuristic scan found no credentials; this does not replace review of future additions.

## Device acceptance still required

1. Install on paired iPhone and Watch with locally configured signing and App Group entitlements. No credentials belong in the repository.
2. Switch Settings → Language between system, Chinese and English; check sheets and return navigation without losing a draft.
3. Set personal goals, record a real intake on iPhone, and verify individual HealthKit samples in the synchronization screen. Check Watch values, pending status and update time.
4. Undo/restore that intake and verify both HealthKit samples and the Watch projection.
5. Inspect four complication families on compatible faces and small/large displays. Check stale display after midnight, disconnected phone and timezone change.
6. WidgetKit/WatchConnectivity delivery is scheduled by the system, not guaranteed instantaneous. Watch runtime/device execution and paired transfer have not been validated in this session; only Watch compilation has.

A later build against the specific physical Watch exposed a provisioning failure: both the Watch app and complication development profiles excluded that device. Generic signed/unsigned builds cannot detect this. Device discovery, a live local-network tunnel and Developer Mode were confirmed separately. Use the OpenIntakeWatch scheme and the actual paired Watch as destination; Xcode automatic signing must include it in both targets' development profiles. Device/account identifiers and provisioning files remain outside the repository.

### Physical Watch installation follow-up (2026-10-22)

Automatic provisioning updates resolved the two device-exclusion errors. The build targeting the actual Watch succeeded. First installation failed with CoreDevice 3002 / IXRemoteErrorDomain 6 (remote connection closed); a single retry installed successfully and CoreDevice then confirmed process launch. This verifies signing, transfer and launch, not WatchConnectivity data delivery or all complication layouts. No intake was created during this check.
