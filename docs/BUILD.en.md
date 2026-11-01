# Build and install on your own devices

[English](BUILD.en.md) · [简体中文](BUILD.zh-CN.md) · [README](../README.md)

## 1. Get the source and tools

1. In [Releases](https://github.com/Eason556-dev/openintake/releases), choose a version → Assets → download its `OpenIntake-<version>-source.zip` and checksum.
2. In Terminal in the download folder, verify the `.sha256` with `shasum -a 256 -c <downloaded-checksum-file>`. The result should say OK.
3. Double-click the ZIP in Finder. Keep the entire extracted folder together; the project references adjacent App, Shared, Config and source folders.
4. Install Xcode from Apple, open it once and finish its required components/license setup yourself. This release was verified with Xcode 27.2. Use a Mac compatible with that Xcode and install iOS/watchOS platform support from Xcode Settings → Components/Platforms as offered by your version. [Apple requirements](https://developer.apple.com/xcode/system-requirements/).
5. Open `OpenIntake.xcodeproj`, not `Package.swift`. Package.swift is for core tests, not the phone app.

## 2. Configure your own identifiers

Do not use the maintainer's Apple account, certificates or profiles. They are not included.

In Finder duplicate `Config/Local.example.xcconfig`, rename the copy `Local.xcconfig` and place it inside Config. In Terminal, from the source folder, this creates the file only if it does not already exist:

```sh
test -f Config/Local.xcconfig || cp Config/Local.example.xcconfig Config/Local.xcconfig
```

Edit the two example values to unique values of your own. For example, if your own prefix is `org.example.intakepreview`:

```text
OPENINTAKE_BUNDLE_ID = org.example.intakepreview
OPENINTAKE_APP_GROUP = group.org.example.intakepreview.shared
```

`org.example` is illustrative; choose your own unique prefix rather than copying it unchanged. Do not change the public defaults to your personal identifiers. `Local.xcconfig` is ignored by Git and source packaging.

The generated project automatically derives:

| Target | Derived bundle ID |
| --- | --- |
| OpenIntake | `org.example.intakepreview` |
| OpenIntakeWidgets | `org.example.intakepreview.widgets` |
| OpenIntakeWatch | `org.example.intakepreview.watchkitapp` |
| OpenIntakeComplications | `org.example.intakepreview.watchkitapp.complications` |

The Watch companion reference uses the same base prefix. Do not rename only the phone target's bundle ID in isolation.

## 3. Sign all four targets

1. Xcode → Settings → Accounts → add your own Apple account. Finish authentication and any Apple terms yourself.
2. Select the blue **OpenIntake** project in the navigator. Under **TARGETS**, select **OpenIntake** → Signing & Capabilities.
3. Enable **Automatically manage signing** and select your own **Team**.
4. Repeat for **OpenIntakeWidgets**, **OpenIntakeWatch** and **OpenIntakeComplications**, using the same Team. Alternatively set your own Team ID only in Local.xcconfig.
5. Keep **HealthKit** on OpenIntake. All four targets have **App Groups**: register/select the same group matching `OPENINTAKE_APP_GROUP`. Let Xcode create profiles, or manage them in your own Apple Developer account.
6. Resolve any red signing errors before running. Apple capability support depends on membership and platform. A free Personal Team may not support the complete capability set; this project does not promise free-account full-device deployment. [Capability overview](https://developer.apple.com/help/account/capabilities/capabilities-overview) · [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).

If your Team cannot provision App Groups or HealthKit, inspect the UI in Simulator or use an eligible Team. Deleting capabilities changes functionality and is not a successful full installation.

## 4. Run iPhone first

1. Connect iPhone to the Mac with a data cable. Unlock it; approve **Trust This Computer** on your own device.
2. Enable **Settings → Privacy & Security → Developer Mode** when requested. Restart and confirm on the phone. [Apple Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
3. In Xcode, open Device Hub / Devices and Simulators (the name varies by version). Wait for device preparation to finish and the phone to be available/Ready.
4. In the top toolbar choose scheme **OpenIntake**, then your physical iPhone as destination. Choose **Product → Run (⌘R)**. Xcode builds, signs, installs and launches the app; there is no separate unsigned IPA installation step.
5. If iOS asks you to trust a development identity, follow its Settings → General → VPN & Device Management instructions for your own team. Never trust an unknown maintainer profile.
6. In OpenIntake select the Health nutrition types you intend to write. Permissions are per type. Previously denied types may need changing in Apple Health → profile/data access → OpenIntake; menu wording depends on iOS.

## 5. Install the companion on Apple Watch

1. Pair the Watch with the iPhone from step 4. Keep both unlocked, nearby and connected, with Bluetooth/Wi-Fi enabled.
2. If Xcode requests it, enable Developer Mode on the Watch and follow its restart/confirmation steps.
3. Open Device Hub and wait until the paired Watch is available. The Watch normally uses the paired iPhone for this setup; not every watch is a separately cabled Mac destination.
4. Choose scheme **OpenIntakeWatch**, destination **your Watch**, then **⌘R**. Check signing for the Watch and complications targets if it fails.
5. Open the phone app so it can send products and today's snapshot. Configure new products on the phone, then test one Watch record. A Watch “sent” status is distinct from verified HealthKit writing on iPhone.
6. To add a complication: long-press a compatible watch face → Edit → Complications → OpenIntake. Available positions depend on the face.

## 6. Validate recording and Health sync

Use your own real quantities or clearly marked disposable test entries. For a synthetic test, undo it afterward in OpenIntake and confirm its own samples are removed.

- Save a product: no intake event or Health sample should appear merely from saving/scanning.
- Record actual product quantity: inspect the sync center, then Apple Health → Browse → Nutrition → the corresponding nutrient → Show All Data. Check value, time and OpenIntake as source. Sample menu names vary by iOS.
- Enter `Rice 150 g, Tea 250 mL`: Record works without a checkbox. With no nutrient values it is **local only** and must not claim Health sync. Fill a known label value only when you have a source; it should scale by actual quantity.
- Deny one write permission: the local record remains pending with a reason. Restore permission and retry; no duplicate samples should be created.
- Undo/restore: original time and quantity should be retained; undo must remove corresponding own Health samples.
- Log one 250 mL water event on Watch: after delivery the phone should show one 250 mL event, not 500 mL. Disconnect/reconnect and check it does not duplicate.
- Change app language and inspect phone, Watch and widgets after delivery/refresh. System permission sheets use system language settings.

## Simulator and command-line checks

Choose OpenIntake + an iPhone Simulator → ⌘R for a UI preview. Simulator camera and Health behavior do not establish physical-device acceptance.

From the source folder:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenIntake.xcodeproj -scheme OpenIntake \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/OpenIntake-build \
  CODE_SIGNING_ALLOWED=NO build
```

Use your installed Xcode path if different. Run `python3 scripts/generate_project.py` only after adding/removing Swift files or changing generator-controlled project configuration. Personal signing belongs in Local.xcconfig because regeneration replaces project settings.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Signing/profile/capability error | Check all four targets, same Team, unique derived IDs, registered App Group and membership eligibility. Do not ask another person for their certificate. |
| Phone/Watch unavailable | Unlock both, reconnect the data cable, confirm trust and Developer Mode, wait for platform support/preparation, then check Device Hub. |
| White screen under debugger | Check whether Xcode is paused on a breakpoint; Continue or disable the breakpoint. If still blank without a paused debugger, inspect the crash/console output. |
| Record disabled | Check the displayed validation reason: empty name, missing/invalid quantity, stale edited text or in-progress submission. No checkbox or AI is required. |
| Unknown-only meal not in Health | Expected: there is no known nutrition to write. Its quantities remain in local history. |
| No authorization sheet appears again | iOS may not repeat a decided request. Check current per-type status and change permissions in Apple Health. |
| Widgets empty or stale | Open the phone app, configure a product, check the matching App Group, then allow system refresh or re-add the widget. |
| Watch says sent but Health is pending | Delivery acknowledgement is not Health verification. Check the phone's sync center and permissions. |

[Apple: run on simulator or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).
