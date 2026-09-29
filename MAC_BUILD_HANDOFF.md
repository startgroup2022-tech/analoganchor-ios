# Analog Anchor — Mac Build Handoff

This workspace is prepared for transfer to a Mac. Nothing here was built with
Xcode (the preparation environment was Linux). Follow the steps below to
generate the project, build it, and validate it on a real iPhone.

## Requirements

- macOS
- Xcode
- XcodeGen
- Apple Developer account
- Compatible iPhone for device validation

## Generate Xcode Project

    cd AnalogAnchorWorkspace

    xcodegen generate

`project.yml` is the single source of truth. The checked-in
`AnalogAnchor.xcodeproj/` directory is empty on purpose — regenerate it, do not
hand-edit it.

## Open Project

    open AnalogAnchor.xcodeproj

## Xcode Configuration

Select the AnalogAnchor scheme.

Configure the Apple Developer Team.

Verify:

- Family Controls
- App Groups
- NFC
- Extension targets
- Signing

`DEVELOPMENT_TEAM` is intentionally blank in `project.yml`; set your Team ID in
Xcode (Signing & Capabilities) for all targets.

## Required Extensions

- AnalogAnchorShieldConfiguration
- AnalogAnchorShieldAction
- AnalogAnchorDeviceActivityMonitor
- AnalogAnchorDeviceActivityReport

All four are already embedded by the app target. Do not add or remove any.

## Real Build

Run a real Xcode build.

Do not replace Apple APIs with mocks.

Do not remove capabilities to bypass signing.

## Real Device Validation

Validate on an iPhone:

- App launch
- Onboarding
- Family Controls authorization
- FamilyActivityPicker
- Screen Time Shield
- Shield Action
- Emergency flow
- DeviceActivity Monitor
- DeviceActivity Report
- Fajr
- Notifications
- Location
- Mosque lookup
- Motion
- NFC
- Bluetooth / Partner

Hardware and system-integration features cannot be validated in the Simulator:
NFC, Bluetooth, Motion, and parts of Family Controls / DeviceActivity behaviour
require a physical device.

## Current Environment

Xcode build was NOT executed because the current environment is Linux.

Real iPhone validation was NOT executed because no iPhone is available.

Linux tests were executed separately and must be reported with the actual result.

---

## Reference — targets and identifiers

| Target | Type | Bundle ID | Extension point |
|---|---|---|---|
| AnalogAnchor | application | `com.analoganchor.app` | — |
| AnalogAnchorShieldConfiguration | app-extension | `com.analoganchor.app.shieldconfiguration` | `com.apple.ManagedSettingsUI.shield-configuration-service` |
| AnalogAnchorShieldAction | app-extension | `com.analoganchor.app.shieldaction` | `com.apple.ManagedSettings.shield-action-service` |
| AnalogAnchorDeviceActivityMonitor | app-extension | `com.analoganchor.app.deviceactivitymonitor` | `com.apple.deviceactivity.monitor-extension` |
| AnalogAnchorDeviceActivityReport | app-extension | `com.analoganchor.app.deviceactivityreport` | `com.apple.deviceactivityui.report-extension` |
| AnalogAnchorKitTests | bundle.unit-test | `com.analoganchor.app.kittests` | — |

- `AnalogAnchorKit` is a local Swift package (`AnalogAnchorKit/`), not a build target.
- App Group used everywhere: `group.com.analoganchor.app`.
- Family Controls entitlement is required on the app and all four extensions.
  Family Controls (Distribution) approval from Apple is required before an
  App Store archive will sign.
- Deployment target: iOS 17.0. Swift version: 5.9.

## Reference — known items to review on Mac (not blockers)

- `DEVELOPMENT_TEAM` empty in `project.yml` (set in Xcode).
- `AnalogAnchor/Resources/Info.plist` contains
  `com.apple.developer.nfc.readersession.iso7816.select-identifiers`
  (`D2760000850101`), consistent with the existing `NFCService` `.iso7816`
  handling. Confirm during App Store review.
- Mosque sanctuary default coordinate mirrors the Android founder-sanctuary
  default; confirm the intended default for iOS.
- `UIBackgroundModes = ['bluetooth-peripheral']` is declared in the app
  `Info.plist`; confirm it matches the shipped Partner behaviour.
