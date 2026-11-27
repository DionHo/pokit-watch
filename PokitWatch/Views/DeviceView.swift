import PokitKit
import SwiftUI

/// Details of the bound device, a few device actions, and "disconnect".
struct DeviceView: View {
    @EnvironmentObject private var pokit: PokitCentral

    var body: some View {
        List {
            if let device = pokit.device {
                Section {
                    LabeledContent("Name", value: device.name)
                    LabeledContent("Model", value: device.product.displayName)
                    LabeledContent("Status") {
                        Text(connectionText)
                    }
                }

                if let status = pokit.status, pokit.phase == .ready {
                    Section("Battery") {
                        LabeledContent("Voltage", value: String(format: "%.2f V", status.batteryVoltage))
                        LabeledContent(
                            "Level",
                            value: "≈ \(Int((status.estimatedBatteryLevel(for: device.product) * 100).rounded())) %"
                        )
                        if status.batteryStatus == .low {
                            Label("Battery low", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if let charging = status.chargingStatus {
                            LabeledContent("Charging") {
                                Text(chargingText(charging))
                            }
                        }
                        if let position = status.switchPosition {
                            LabeledContent("Switch") {
                                Text(switchText(position))
                            }
                        }
                    }
                }

                if pokit.canFlashLED || pokit.hasTorch {
                    Section {
                        if pokit.canFlashLED {
                            Button {
                                pokit.flashLED()
                            } label: {
                                Label("Flash LED", systemImage: "lightbulb.fill")
                            }
                        }
                        if pokit.hasTorch {
                            Toggle(isOn: Binding(
                                get: { pokit.torchIsOn ?? false },
                                set: { pokit.setTorch($0) }
                            )) {
                                Label("Torch", systemImage: "flashlight.on.fill")
                            }
                        }
                    }
                }

                Section("Device") {
                    if let firmware = pokit.details.characteristics?.firmwareVersion ?? pokit.details.firmwareRevision {
                        LabeledContent("Firmware", value: firmware)
                    }
                    if let hardware = pokit.details.hardwareRevision {
                        LabeledContent("Hardware", value: hardware)
                    }
                    if let serial = pokit.details.serialNumber {
                        LabeledContent("Serial", value: serial)
                    }
                    if let mac = pokit.details.characteristics?.macAddress {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Address")
                            Text(verbatim: mac)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        pokit.forgetDevice()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                } footer: {
                    Text("Disconnecting forgets this device. You can then pick another one.")
                }
            }

            Section {
                LabeledContent("App", value: appVersion)
                NavigationLink(value: Route.diagnostics) {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
            } footer: {
                Text("Unofficial app, not affiliated with Pokit Innovations.")
            }
        }
        .navigationTitle("Device")
    }

    private var connectionText: LocalizedStringKey {
        switch pokit.phase {
        case .ready: return "Connected"
        case .preparing: return "Connecting…"
        case .idle, .scanning, .connecting: return "Searching…"
        }
    }

    private func chargingText(_ status: ChargingStatus) -> LocalizedStringKey {
        switch status {
        case .discharging: return "On battery"
        case .charging: return "Charging…"
        case .charged: return "Charged"
        }
    }

    private func switchText(_ position: SwitchPosition) -> LocalizedStringKey {
        switch position {
        case .voltage: return "Voltage"
        case .multiMode: return "Multi"
        case .highCurrent: return "High current"
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// The rolling record of link events, newest first. Meant to be screenshotted when
/// something does not work, so the entries are plain technical English.
struct DiagnosticsView: View {
    @ObservedObject var log: DiagnosticsLog

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text("Nothing recorded yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(log.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.time, format: .dateTime.hour().minute().second())
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(verbatim: entry.text)
                        .font(.system(size: 12, design: .monospaced))
                }
                .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
            }
        }
        .navigationTitle("Diagnostics")
    }
}
