# Watch quick intake and automatic sync (0.6.1, build 15)

## Authority and delivery

The iPhone library is the only intake ledger and the only HealthKit writer. Watch sends immutable commands containing a UUID, timestamp, actual quantity, unit, product ID and expected recipe revision. It never sends a replacement daily total or writes HealthKit independently.

- Watch persists each request atomically before transmission. An unavailable/corrupt outbox blocks new entries rather than replacing existing data.
- `transferUserInfo` queues background delivery; `sendMessage` provides a fast path when reachable. Both can deliver the same UUID; this is intentional and idempotent.
- iPhone validates the command against its current product catalog, then saves the event UUID, frozen recipe and original command together to the existing library/outbox before acknowledging acceptance.
- A repeated matching UUID returns acceptance without creating another event. A changed payload with the same UUID is rejected. Accepted events retain identity through HealthKit retry, deletion and restoration; late Watch delivery cannot resurrect a revoked event.
- Transport completion is not an intake acknowledgement. Only durable phone acceptance removes a Watch outbox item. Rejected commands remain visible for review; transient storage/lock errors retain the request for retry.
- Existing near-duplicate checks remain in effect for different commands close in time. Potential duplicates are explicitly rejected for review, never silently counted twice or silently merged.
- The phone publishes fresh dashboard/catalog state on every persisted change, activation, reachability change and protected-data availability. Watch requests refresh on activation and uses received state to retry pending transfers. No manual refresh is required in normal use.
- Pending HealthKit operations retry automatically with bounded backoff while execution is available; permissions are checked per type and saved samples are verified. Automatic retries do not present permission dialogs. All background work remains subject to OS scheduling and file protection; offline/locked devices cannot guarantee immediate sync.

Watch shows phone-confirmed totals, with unacknowledged Watch entries in a separate pending list. It deliberately does not add optimistic quantities to a phone total that may already contain those same entries.

## Products and privacy

Watch receives configured eligible product names, IDs, revision tokens, quantity units and defaults. It does not receive OCR text, photos or complete ingredient/health histories. New products and recipe editing remain on iPhone. Changing any saved recipe advances its revision: an offline Watch request based on the old revision is rejected for review rather than silently using different nutrition values. All accepted requests route supported values through the existing phone HealthKit outbox; unknown nutrients remain absent.

Watch state is stored locally using protected files. Phone library protection is unchanged. No account, server, third-party API or mandatory AI is added. The transfer queue and catalog contain private user data and must not be committed or exported into the public repository.

## Complications

Rectangular complications now use a compact three-line layout within WidgetKit content margins, shrink long text and omit the extra footer that overflowed the Modular large slot. The pending indicator remains. Full-color faces receive metric colors; accented faces use `widgetAccentable` so the face's selected monochrome color controls emphasis. The system determines rendering mode, not a forced app color override.

## Validation

- 162 core tests pass, including 13 Watch tests: replay, restart/lost acknowledgement, undo/restore with late replay, conflicting IDs, independent phone/Watch events, near-duplicate rejection, out-of-order events, product edit/removal, invalid quantities/time/unit, durable outbox receipts, explicit rejection, g/mL food scaling, and mocked HealthKit permission denial/partial write/retry/undo/restore.
- 250 mL retransmitted 20 times produces one event. Shared mocked HealthKit retry leaves one 250 mL sample. Two genuinely separate 250 mL events total 500 mL.
- iOS, widget, Watch and complication targets build unsigned; the paired app bundle also builds signed.
- Mock tests are not real HealthKit or WatchConnectivity delivery acceptance. No fabricated intake is written to user devices.

Device checklist: record a real 250 mL drink on Watch, confirm one phone history event and one Apple Health sample; relaunch both apps and verify the total does not increase; repeat offline and reconnect; change a product on iPhone before delivering an old offline request and check the explicit rejection; undo on phone and confirm the Watch total updates; inspect Modular rectangular layout with full-color and single-color faces, including large accessibility text. Background delivery may be delayed by the OS. Foreground or unlocking resumes automatic retries.

References: [Apple Watch Connectivity](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity), [Widget rendering modes](https://developer.apple.com/documentation/WidgetKit/WidgetRenderingMode).
