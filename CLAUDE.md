# pokit-watch

watchOS app that talks to a Pokit Meter / Pokit Pro multimeter over Bluetooth LE directly from
the Apple Watch. The owner has a Windows PC, an iPhone and an Apple Watch, and **no Mac**.

## Where things are

- `PokitKit/` – Swift package with the protocol (UUIDs, settings/reading/status encoding, range
  tables, value formatting). No Apple frameworks; unit-tested.
- `PokitWatch/` – the watch app. `Bluetooth/PokitCentral.swift` is the connection state machine
  (scan, connect, auto-reconnect, watchdog, background/foreground). `Views/` is SwiftUI.
- `PokitPhone/` – minimal iOS host app; it only exists to carry the watch app.
- `project.yml` – XcodeGen definition. The `.xcodeproj` and the `Info.plist` files are generated.
- `docs/PROTOCOL.md` – byte-level protocol reference with sources. Read it before touching the
  protocol or adding the oscilloscope / data logger.
- `docs/DEPLOYMENT.md` (German) – how the app gets onto the watch: TestFlight, or a free
  Apple ID for 7 days.

## Building and checking

Nothing Apple-specific can be built locally without a Mac. GitHub Actions is the compiler:

- `swift test --package-path PokitKit` runs the protocol tests wherever a Swift toolchain exists
  (Linux, macOS, Windows).
- Every push runs `.github/workflows/build.yml`: PokitKit tests, simulator build, unsigned device
  archive, bundle checks, simulator screenshots, and the artifact `PokitWatch-unsigned-ipa`.
  A run takes about 10 minutes. Follow it with `gh run watch`, fetch the IPA with
  `gh run download <run-id> -n PokitWatch-unsigned-ipa`.
- A commit message containing `[screenshots]` makes CI commit fresh screenshots to
  `docs/screenshots/` on that branch. Pull before the next push. Use it for UI changes only;
  the screenshots are the only way to see the UI without a device.
- The simulator has no Bluetooth. The app has a demo mode for it: launch arguments
  `-PokitDemo meter|pro|list`, `-meter.mode <raw value>`, `-PokitDemoScreen modes|ranges|device`.
- `.github/workflows/testflight.yml` is started by hand and needs Apple Developer secrets.
  It has never run.

Because a compile error costs a full CI round trip, keep changes small, stay with APIs that
exist on watchOS 10, and read the surrounding code before editing. Swift language mode is 5.

## State of things

- Verified: protocol tests (byte captures from real devices, via dokit), CI builds, UI in the
  simulator on 40 mm and 46 mm.
- **Not verified: anything on real hardware.** The Bluetooth code has been reviewed but never
  talked to a Pokit. Expect the first device test to find problems.
- There is no way to read logs from the watch without Xcode. To debug behaviour on the device,
  ask what the screen shows, and if that is not enough add an on-device diagnostics view
  (a rolling log of connection events) rather than guessing.

## Conventions

- Code, comments, README and commit messages are in English; `docs/DEPLOYMENT.md` and
  conversation with the owner are in German. UI strings are English in code, with German in
  `Localizable.xcstrings` (keep both catalogs in step when adding strings; mode titles from
  `MultimeterMode.title` are localisation keys too).
- Comments explain why, not what.
- Never commit signing material (`.p8`, `.p12`, profiles) or Apple ID details.
- Unofficial project: no Pokit branding or assets. The app is called **Wristmeter** (App Store
  Connect record, home-screen name on phone and watch). "Pokit" is a registered trademark of
  Pokit Innovations: use it only to refer to the meters ("works with Pokit Meter"), never as
  or in the app's own name. Repo, target, folder and bundle-ID names are internal and stay.
