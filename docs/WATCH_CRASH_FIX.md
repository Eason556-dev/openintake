# Watch synchronization crash — 0.6.2 / build 16

## Evidence (2026-10-23)

Two physical Watch crash reports from build 15 show EXC_BREAKPOINT / SIGTRAP on a utility NSOperationQueue. The exact matching debug binary symbolicates the app frames to `closure #1 in WatchStore.refresh()` and its dictionary completion thunk, above WatchConnectivity and Swift concurrency / dispatch frames. This identifies the synchronization reply callback, rather than a nutrition calculation or duplicate Health write. Raw device crash reports and identifiers remain outside this repository.

The installed WatchConnectivity SDK declares `sendMessage` reply/error blocks without Sendable annotations. Creating these completion closures inside the main-actor store permits actor isolation to be inherited; the real Watch runtime traps when WatchConnectivity invokes the block on its background queue. Merely putting a Task inside the block is too late to prevent an entry isolation assertion.

## Fix

`Shared/ConnectivityCallbacks.swift` constructs an explicitly Sendable completion outside actor isolation. It extracts only Data values from the Objective-C dictionary, then explicitly hops to MainActor to mutate the store. Both refresh and intake replies use it. The phone and Watch error handlers likewise use an explicitly Sendable handler. Delegate methods remain nonisolated and perform their existing main-actor hops. No concurrency checking is disabled; no automatic synchronization is removed.

The phone also refuses to publish an empty dashboard/catalog while its protected library is unreadable. It keeps the last successful projection until unlock/reload, instead of making an unavailable library look like an empty one.

## Verification

- 165 tests pass, including three new tests invoking the callback from background tasks, concurrent malformed replies and background error delivery. These are host tests, not replacements for physical Watch acceptance.
- All four targets build unsigned; signed device build and physical repeated-refresh results are recorded below once completed.
- A DEBUG-only `--watch-sync-audit` launch option requests twelve refreshes and writes a small diagnostic containing completion and reply count. It creates no intake and includes no product names or Health data.

The already implemented Watch quick entry, persistent request queue, event-ID deduplication, shared phone HealthKit writer and complication rendering fixes remain in place. See [Watch sync design](WATCH_SYNC.md).

### Deployment status

The 0.6.2 / build 16 signed build succeeded and both the paired iPhone and Watch accepted the update on 2026-10-23. The initial phone foreground launch was rejected by iOS because the device was locked; this is distinct from the fixed Watch callback crash. Repeated live refresh acceptance requires an unlocked device session and is not implied by the host tests or installation success.

### Physical refresh acceptance (2026-10-23)

After the user unlocked both devices, the iPhone app launched successfully. Two separate Watch launches completed the DEBUG refresh audit: 2 replies in the first run and 8 in the second (each requested 12 refresh attempts). The UI rendered the dashboard and log-intake entry, and the Watch main process remained present after the second run. Not every attempt produced an immediate reply; this is not a 24/24 delivery guarantee.

The additional crash reports retrieved during verification were both version 0.6.1 / build 15, not the fixed build 16. A subsequent file-list query encountered a transient CoreDevice streaming error and was retried. No synthetic intake was submitted; these runs exercise live synchronization replies and UI updates, not real HealthKit write acceptance. Full-color/monochrome complication layouts and a real user-created intake still follow the separate device checklist.
