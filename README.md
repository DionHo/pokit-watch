# pokit-watch

Use a [Pokit](https://www.pokitinnovations.com/) multimeter on the Apple Watch directly, without a phone.

The watch app talks to a **Pokit Meter** or **Pokit Pro** over Bluetooth LE and shows the reading
on your wrist. The iPhone is only needed to install the app.

> Unofficial project, not affiliated with Pokit Innovations. Measuring mains or other dangerous
> voltages is at your own risk; the watch is a display, not a safety device.

## What it does

- Finds Pokit devices, remembers the one you picked and **reconnects on its own** whenever the
  meter is switched on and in range.
- Multimeter modes: DC/AC voltage, DC/AC current, resistance, continuity, diode, temperature,
  plus capacitance and external temperature on the Pokit Pro.
- Auto-range or a fixed range; the display keeps the decimal point steady per range, like a
  bench meter (`12.3 mV`, `4.987 V`, `1.234 kΩ`).
- **Continuity on the wrist**: haptic tap and a green screen while there is continuity
  (the Pokit itself has no beeper).
- Hold (tap the value, or press the button on a Pokit Pro), running min/max.
- Battery state, firmware and serial number, flash the LED (Meter), torch (Pro).
- English and German.

A watchdog looks after the connection: if readings stop, the app first asks the meter again and,
if the link is really dead, reconnects from scratch.

## Using it

1. Switch the Pokit on and open **Pokit** on the watch.
2. Tap your meter in the list. From then on the app connects to it automatically.
3. Tap the mode line at the top to change the mode, the range button to change the range,
   the value (or the pause button) to hold. The battery icon opens the device page.

Tips:

- watchOS returns to the watch face after a while. To keep the meter in front, set
  *Settings › General › Return to Clock › Pokit* to *After 1 hour* on the watch.
- When the app goes to the background the meter is put into idle to save its battery;
  measuring resumes when you raise your wrist.
- Pokit Pro: the physical switch on the device decides which modes work. The app shows a hint
  if the selected mode does not match the switch.

## Installing it

There is no App Store version. You build it yourself and install it through TestFlight; this
works **without a Mac**, using GitHub Actions. It needs an Apple Developer Program membership.

Step-by-step guide (German): [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)

If you do have a Mac: `brew install xcodegen && xcodegen generate`, open `PokitWatch.xcodeproj`,
pick your team for both targets and run the `PokitWatch` scheme on your iPhone/watch.

## Project layout

| Path | What |
|---|---|
| `PokitKit/` | Swift package with the Pokit protocol: UUIDs, settings/reading/status encoding, range tables for Meter and Pro, value formatting. No Apple frameworks, so it is unit-tested on Linux too. |
| `PokitWatch/` | The watchOS app (SwiftUI + CoreBluetooth). `Bluetooth/PokitCentral.swift` owns the connection. |
| `PokitPhone/` | Minimal iOS host app. It exists because TestFlight delivers watch apps inside an iOS app. |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) definition; the Xcode project is generated, not committed. |
| `.github/workflows/build.yml` | Tests and unsigned builds on every push. |
| `.github/workflows/testflight.yml` | Manual: sign and upload to TestFlight. |

Run the protocol tests with `swift test --package-path PokitKit` (macOS or Linux).

## Protocol notes

The byte layouts come from Pokit's *Bluetooth API Definition* (D0005250) and from
[dokit](https://github.com/pcolby/dokit), which reverse-engineered the Pokit Pro additions.
A few things worth knowing:

- Meter and Pro are told apart by the Status service UUID (`…aec4` vs `…aec5`); their range
  tables differ completely, so the range byte only means something together with the product.
- A measurement starts by writing mode, range and update interval to the multimeter Settings
  characteristic; readings then arrive as notifications. Writing mode 0 (idle) stops it.
- The status byte of a reading is an enum whose meaning depends on the mode (auto-range on/off,
  continuity yes/no, 255 = error).
- Not implemented yet: oscilloscope (DSO) and data logger.

## Credits

- [dokit](https://github.com/pcolby/dokit) by Paul Colby for the protocol documentation.
- Pokit Innovations for publishing the Bluetooth API.

MIT licensed, see [LICENSE](LICENSE).
