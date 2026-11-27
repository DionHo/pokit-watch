# pokit-watch

watchOS app that talks to a Pokit Meter / Pokit Pro multimeter over Bluetooth LE directly from
the Apple Watch. The owner has a Windows PC, an iPhone and an Apple Watch, and **no Mac**.

## Where things are

- `PokitKit/` – Swift package with the protocol (UUIDs, settings/reading/status encoding, range
  tables, value formatting). No Apple frameworks; unit-tested.
- `PokitWatch/` – the watch app. `Bluetooth/PokitCentral.swift` is the connection state machine
  (scan, connect, auto-reconnect, watchdog, background/foreground) and drives the three tools:
  multimeter, oscilloscope, data logger (`tool`; state in `ToolStates.swift`). `Views/` is SwiftUI.
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
  (Linux, macOS, Windows). In a Linux session without one, Docker does it (start `dockerd` if
  it is not running): `docker run --rm -v "$PWD/PokitKit":/pkg -w /pkg swift:6.2-noble swift test`.
  The same image catches syntax errors in the app sources before a CI round trip:
  `swiftc -frontend -parse PokitWatch/**/*.swift PokitWidgets/*.swift` (syntax only, no types).
- Every push runs `.github/workflows/build.yml`: PokitKit tests, simulator build, unsigned device
  archive, bundle checks, simulator screenshots, and the artifact `PokitWatch-unsigned-ipa`.
  A run takes about 10 minutes. Follow it with `gh run watch`, fetch the IPA with
  `gh run download <run-id> -n PokitWatch-unsigned-ipa`.
- A commit message containing `[screenshots]` makes CI commit fresh screenshots to
  `docs/screenshots/` on that branch. Pull before the next push. Use it for UI changes only;
  the screenshots are the only way to see the UI without a device.
- The simulator has no Bluetooth. The app has a demo mode for it: launch arguments
  `-PokitDemo meter|pro|list`, `-meter.mode <raw value>`,
  `-PokitDemoScreen modes|ranges|device|log|refused`, `-PokitDemoTool scope|logger`.
- `.github/workflows/testflight.yml` is started by hand (pick the branch to ship) and needs the
  Apple Developer secrets, which are set in this repository. It archives unsigned, then signs
  with Apple's cloud-managed certificate during export and uploads; that works (first upload
  2026-11-27). A run takes about 3 minutes, plus Apple's processing before TestFlight offers
  the build. App Store Connect warns that uploads need the iOS 27 SDK (Xcode 27) from April
  2027: move the runner image or select the newer Xcode before then. The build number is the
  UTC time of the run (`yymmddHHMM`), which tells which commit a build in TestFlight came from.
  Start a run only when the owner asks for it.

Because a compile error costs a full CI round trip, keep changes small, stay with APIs that
exist on watchOS 10, and read the surrounding code before editing. Swift language mode is 5.

## State of things

- Verified: protocol tests (byte captures from real devices, via dokit), CI builds, UI in the
  simulator on 40 mm and 46 mm, signing and upload to TestFlight.
- On real hardware: version 0.1.0 was installed through TestFlight and worked against the
  owner's meter (2026-11-27). About 0.3.0 (connected only while on screen, complications,
  oscilloscope, data logger, diagnostics) the owner reported "looks good with both devices",
  which reads as: they have a Pokit Meter and a Pokit Pro. That is a general verdict, not a
  feature-by-feature check, so the protocol uncertainties below still stand until something
  more specific comes back.
- The one problem reported with 0.3.0: on the Pokit Pro, a mode picked while the switch is in
  the wrong position is refused ("Mode not available") and stayed refused after the switch
  was corrected. 0.3.1 answers that with a retry button in place of the range/hold controls
  (`retryMode`), a restart as soon as Status reports another switch position (`switchMoved`),
  and an idle command before the retried mode. Why the plain repeat every 4 s did not get the
  mode going is not known.
- 0.3.1 on the owner's watch (2026-11-27): "only a black screen after a device was detected".
  Cause not found. Reading the 0.3.0 -> 0.3.1 diff shows nothing that runs differently on a
  normal connect, and no view can be empty, so it looks like a hang or crash on a path only a
  real device takes (refused mode at connect, switch change) or something outside the diff.
  Open questions to the owner: whole screen black or only the content (toolbar still there),
  which device, the Pro's switch position, and whether 0.3.0 (TestFlight, previous builds)
  still works. Do not ship further guesses on top of 0.3.1 before that is answered.
- `main` only has what was merged with PR #2 (the Wristmeter rename and docs). Later work sits
  on the work branch until the owner asks for a PR.
- Offered to the owner, not built: a wrist-down timeout that disconnects independently of
  watchOS's "Return to Clock" setting; quick-start complications for more modes.
- Oscilloscope and data logger are implemented from the documentation and dokit's byte vectors
  only; whether a real device behaves as assumed (order of Metadata and samples, the Pro's
  sample counts, what a multimeter command does to a running log) is unverified until the
  owner has tried them. The app never writes a multimeter or oscilloscope command while the
  logger reports that it is recording, and after connecting it waits for the logger's state
  before the first command; keep it that way.
- The link to the meter exists only while the app is on screen (`setAppActive` in
  `PokitCentral`, driven by `scenePhase`): going to the background writes idle and
  disconnects, becoming active reconnects. The owner asked for this to spare the meter's
  battery; do not reintroduce background connections or pending connects.
- There is no way to read logs from the watch without Xcode. To debug behaviour on the device,
  ask the owner for a screenshot of *Diagnostics* (device page, bottom): a rolling record of
  link events, commands sent (hex) and metadata received (`DiagnosticsLog`, filled from
  `PokitCentral`). Add entries there for whatever a new feature needs rather than guessing.

## Conventions

- Code, comments, README and commit messages are in English; `docs/DEPLOYMENT.md` is in
  German. Talk to the owner in the language of their last message (German at first, English
  lately). UI strings are English in code, with German in
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
