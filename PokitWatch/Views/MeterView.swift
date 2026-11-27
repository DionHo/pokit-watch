import PokitKit
import SwiftUI

/// The measurement screen: mode on top, the value in the middle, range and hold below.
struct MeterView: View {
    @EnvironmentObject private var pokit: PokitCentral
    @ObservedObject var meter: MeterState
    // The defaults key is only ever set from the command line, for simulator screenshots.
    @State private var showsModes = UserDefaults.standard.string(forKey: "PokitDemoScreen") == "modes"
    @State private var showsRanges = UserDefaults.standard.string(forKey: "PokitDemoScreen") == "ranges"

    var body: some View {
        VStack(spacing: 2) {
            modeButton
            if pokit.phase == .ready {
                Spacer(minLength: 0)
                valueBlock
                Spacer(minLength: 0)
                infoLine
                controls
            } else {
                Spacer(minLength: 0)
                ConnectionStatusView()
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.device) {
                    Image(systemName: batterySymbol)
                }
                .accessibilityLabel(Text("Device"))
            }
        }
        .sheet(isPresented: $showsModes) {
            ModePickerView()
                .environmentObject(pokit)
        }
        .sheet(isPresented: $showsRanges) {
            RangePickerView()
                .environmentObject(pokit)
        }
    }

    // MARK: Pieces

    private var modeButton: some View {
        Button {
            showsModes = true
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: pokit.mode.symbol)
                    .font(.headline)
                Text(LocalizedStringKey(pokit.mode.title))
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var valueBlock: some View {
        VStack(spacing: -2) {
            Text(verbatim: meter.display.value.number)
                .font(.system(size: 58, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .foregroundStyle(valueColor)
            Text(verbatim: meter.display.value.unit)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            pokit.toggleHold()
        }
        .accessibilityElement(children: .combine)
    }

    /// One line under the value: a problem if there is one, otherwise hold or min/max.
    private var infoLine: some View {
        Group {
            if meter.modeWasRejected {
                Label("Mode not available", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if switchMismatch {
                Label("Check the switch on the Pokit", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if !meter.isReceiving {
                Text("Waiting for data…")
                    .foregroundStyle(.secondary)
            } else if meter.isHolding {
                Text(verbatim: "HOLD")
                    .fontWeight(.bold)
                    .foregroundStyle(.yellow)
            } else if let minimum = meter.statistics.minimum,
                      let maximum = meter.statistics.maximum,
                      meter.statistics.count > 1 {
                Text(verbatim: "↓ \(short(minimum))   ↑ \(short(maximum))")
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        pokit.resetStatistics()
                    }
            } else {
                Text(verbatim: " ")
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if pokit.mode.hasRanges {
                Button {
                    showsRanges = true
                } label: {
                    Text(verbatim: rangeText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                }
            }
            Button {
                pokit.toggleHold()
            } label: {
                Image(systemName: meter.isHolding ? "play.fill" : "pause.fill")
                    .frame(maxWidth: pokit.mode.hasRanges ? nil : .infinity)
            }
            .tint(meter.isHolding ? .yellow : nil)
            .accessibilityLabel(Text("Hold"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.footnote)
    }

    // MARK: Derived values

    private var switchMismatch: Bool {
        guard let position = pokit.status?.switchPosition else { return false }
        return !position.isExpectedToSupport(pokit.mode)
    }

    private var hasContinuity: Bool {
        meter.display.hasContinuity == true && meter.isReceiving && !meter.isHolding
    }

    private var backgroundColor: Color {
        hasContinuity ? Color.green.opacity(0.6) : Color.clear
    }

    private var valueColor: Color {
        if meter.isHolding { return .yellow }
        switch meter.display.condition {
        case .error: return .red
        case .overload: return .orange
        case .normal: return meter.isReceiving ? .primary : .secondary
        }
    }

    private var rangeText: String {
        switch pokit.range {
        case .auto:
            if let label = meter.display.rangeLabel {
                return "AUTO · \(label)"
            }
            return "AUTO"
        case .fixed(let index):
            return pokit.device?.product.range(for: pokit.mode, index: index)?.label(unit: pokit.mode.unit) ?? "–"
        }
    }

    private var batterySymbol: String {
        guard pokit.phase == .ready, let status = pokit.status, let product = pokit.device?.product else {
            return "info.circle"
        }
        if status.chargingStatus == .charging {
            return "battery.100percent.bolt"
        }
        switch status.estimatedBatteryLevel(for: product) {
        case ..<0.15: return "battery.0percent"
        case ..<0.4: return "battery.25percent"
        case ..<0.65: return "battery.50percent"
        case ..<0.9: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func short(_ value: Double) -> String {
        MeterDisplay.format(value, mode: pokit.mode).text
    }
}

/// Replaces the value while the watch is looking for, or setting up, the device.
struct ConnectionStatusView: View {
    @EnvironmentObject private var pokit: PokitCentral

    var body: some View {
        VStack(spacing: 6) {
            ProgressView()
            Text(statusText)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Button("Other device") {
                pokit.forgetDevice()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.footnote)
        }
    }

    private var statusText: LocalizedStringKey {
        if pokit.bluetooth != .ready {
            return "Waiting for Bluetooth…"
        }
        if pokit.phase == .preparing {
            return "Connecting…"
        }
        return "Searching for \(pokit.device?.name ?? "Pokit")…"
    }
}
