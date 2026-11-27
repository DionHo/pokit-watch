# pokit-watch

watchOS app that talks to a Pokit Meter / Pokit Pro multimeter over Bluetooth LE directly from
the Apple Watch. The owner has a Windows PC, an iPhone and an Apple Watch, and **no Mac**.

## Where things are

- `PokitKit/` – Swift package with the protocol (UUIDs, settings/reading/status encoding, range
  tables, value formatting). No Apple frameworks; unit-tested.
- `PokitWatch/` – the watch app. `Bluetooth/PokitCentral.swift` is the connection state machine
  (scan, connect, auto-reconnect, watchdog, background/foreground). `Views/` is SwiftUI.
- `PokitWidgets/` – WidgetKit extension: complications for the watch face and the Smart Stack.
  They only launch the app, plain or in a given mode (`QuickStartLink` in PokitKit carries the
  mode to `RootView.onOpenURL`); no data is shared with the app (that would need an app group).
  Complications cannot be rendered in CI, so their layout is unverified until the owner looks.
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
- `.github/workflows/testflight.yml` is started by hand (pick the branch to ship) and needs the
  Apple Developer secrets, which are set in this repository. It archives unsigned, then signs
  with Apple's cloud-managed certificate during export and uploads; that works (first upload
  2026-11-27). A run takes about 3 minutes, plus Apple's processing before TestFlight offers
  the build. App Store Connect warns that uploads need the iOS 27 SDK (Xcode 27) from April
  2027: move the runner image or select the newer Xcode before then.

Because a compile error costs a full CI round trip, keep changes small, stay with APIs that
exist on watchOS 10, and read the surrounding code before editing. Swift language mode is 5.

## State of things

- Verified: protocol tests (byte captures from real devices, via dokit), CI builds, UI in the
  simulator on 40 mm and 46 mm, signing and upload to TestFlight.
- On real hardware: version 0.1.0 was installed through TestFlight and worked against the
  owner's meter (2026-11-27). Everything changed after that is unverified on a device until
  the owner has tried the next TestFlight build; say so when reporting.
- The link to the meter exists only while the app is on screen (`setAppActive` in
  `PokitCentral`, driven by `scenePhase`): going to the background writes idle and
  disconnects, becoming active reconnects. The owner asked for this to spare the meter's
  battery; do not reintroduce background connections or pending connects.
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
- A new target needs its bundle ID registered in the developer portal before the TestFlight
  workflow can sign it; tell the owner and add it to step 2 of `docs/DEPLOYMENT.md`.
- Unofficial project: no Pokit branding or assets. The app is called **Wristmeter** (App Store
  Connect record, home-screen name on phone and watch). "Pokit" is a registered trademark of
  Pokit Innovations: use it only to refer to the meters ("works with Pokit Meter"), never as
  or in the app's own name. Repo, target, folder and bundle-ID names are internal and stay.
