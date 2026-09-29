# AGENTS.md — Analog Anchor (Android → iOS port)

## Repository layout
- `app/` — the **original Android** app (Kotlin/Compose, ~197 files, ~48k LOC). Treat as read-only reference for the iOS port.
- `AnalogAnchorWorkspace/` — the iOS workspace.
  - `AnalogAnchorKit/` — portable Swift package (Domain + Storage). Builds & tests on **Linux** and Apple platforms.
  - `AnalogAnchor/` — SwiftUI app target (App / Features / Services / Resources).
  - `project.yml` — XcodeGen spec; regenerate `AnalogAnchor.xcodeproj` with `cd AnalogAnchorWorkspace && xcodegen generate`.

## Build & test (Linux, no Xcode)
A Swift toolchain is required. On this machine Swift 6.0.3 is extracted at `/tmp/swift-toolchain`
and needs a `libncurses.so.6` shim:

```bash
export PATH=/tmp/swift-toolchain/usr/bin:$PATH
export LD_LIBRARY_PATH=/tmp/swiftlibs   # contains libncurses.so.6 symlink
cd AnalogAnchorWorkspace/AnalogAnchorKit
swift build && swift test               # 58 tests, all domain + storage logic
```
App-target SwiftUI/UIKit sources cannot compile on Linux; verify them with
`swiftc -frontend -parse <file>` per file (the extensions import Apple-only
frameworks, so parse them individually rather than in one command).

## Porting rules
- Never modify/delete `app/` Android sources while porting.
- Domain logic is ported **faithfully** into `AnalogAnchorKit` and covered by tests
  (`PrayerTimesCalculatorTests`, `OpenLocationCodeTests`, `LedgerTests`,
  `TokenCodecTests`, `PoliciesTests`).
- Apple-only APIs are always guarded with `#if canImport(...)` and never imported
  by the Kit, so the package stays Linux-testable.
- Android-only enforcement (Accessibility Service, Overlay, Device Admin) must
  **not** be reproduced. The iOS target is FamilyControls / DeviceActivity /
  ManagedSettings (Phase 3).

## Phase status
- **Phase 1** — Android audit + iOS gap report: done.
- **Phase 2** — iOS *foundation*: portable kit, SwiftUI shell, services, storage,
  Screen Time **authorization only** (no blocking/shields/extensions). Done.
- **Phase 3** — Screen Time engine: shields, DeviceActivity schedules,
  FamilyActivityPicker, Shield Configuration + Shield Action + DeviceActivity
  Monitor extensions. Done.
- **Phase 3.1** — domain-gap fixes: done.
- **Phase 4.1** — build blockers + existing-service integration: done.
  - `AppEnvironment` behavior wiring + `.anchor` pillar fix; single
    `ScreenTimeCoordinator` owned by the app and injected into the provider.
  - `UsageReportSceneView` renders the `DeviceActivityReport` scene so the report
    extension actually runs; Day Guard reads the App-Group snapshot it writes.
  - Report extension entry point is `@main` (this extension point rejects
    `NSExtensionPrincipalClass` on iOS 18+).
  - Partner: real connect/disconnect/state machine wired into `PartnerCircleView`,
    settling through `PartnerDomain`.
  - Fajr: reminder scheduling + miss evaluation on launch/foreground; prayer
    verification in the UI.
  - Mosque: real OpenStreetMap Overpass lookup wired into `MosqueView`.
  - Emergency Protocol re-arms the shield when the active-unlock window closes.
- **Phase 4.2** — not started (Live Activity, Dynamic Island, Focus Filter,
  BGTask, and any domain rebuild are explicitly out of scope for 4.1).

## Screen Time engine (Phase 3)
- Layering is strict: **SwiftUI → `ScreenTimeManager` → `DeviceActivityScheduler`
  / `ManagedSettingsController`**. Views never import ManagedSettings/DeviceActivity.
- Policy + picker selection are stored as JSON in the App Group
  (`SharedPolicyStore`), because the extensions run in separate processes.
  Extensions report failures there too (`DiagnosticRecord`), surfaced in Day Guard.
- Apple limits respected: no app enumeration (FamilyActivityPicker only), no
  "unblock forever" shield action (`.defer`/`.openParentApplication` only), and
  usage is threshold-based (events), not continuous telemetry.
- Required entitlements: `com.apple.developer.family-controls` +
  `com.apple.security.application-groups` (`group.com.analoganchor.app`) on the
  app **and all three extensions**. Family Controls needs Apple approval.
