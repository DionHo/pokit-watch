import PokitKit
import SwiftUI

/// Shown while no device is remembered: the Pokits in range, tap one to bind to it.
struct DeviceListView: View {
    @EnvironmentObject private var pokit: PokitCentral

    var body: some View {
        List {
            if pokit.discovered.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Searching for Pokit devices…")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Text("Switch on your Pokit Meter or Pokit Pro and keep it close.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)

                Button {
                    pokit.rescan()
                } label: {
                    Label("Search again", systemImage: "arrow.clockwise")
                }
            } else {
                Section {
                    ForEach(pokit.discovered) { found in
                        Button {
                            pokit.connect(to: found)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: found.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(verbatim: found.product.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "cellularbars", variableValue: signalLevel(found.rssi))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Tap a device to connect. The watch remembers it.")
                }

                Button {
                    pokit.rescan()
                } label: {
                    Label("Search again", systemImage: "arrow.clockwise")
                }
            }
        }
        .navigationTitle("Wristmeter")
        .onAppear {
            pokit.startScanning()
        }
    }

    /// Maps RSSI (roughly -95 … -50 dBm) to `0...1` for the signal bars.
    private func signalLevel(_ rssi: Int) -> Double {
        guard rssi < 0 else { return 0 } // 127 means "not available"
        return min(1, max(0.1, (Double(rssi) + 95) / 45))
    }
}
