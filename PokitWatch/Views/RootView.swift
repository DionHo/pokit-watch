import PokitKit
import SwiftUI

enum Route: Hashable {
    case device
}

/// Decides which of the three top-level screens is shown: a Bluetooth problem, the device
/// list, or the meter. Once a device is remembered the meter screen stays up, also while
/// the connection is being (re-)established.
struct RootView: View {
    @EnvironmentObject private var pokit: PokitCentral
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch pokit.bluetooth {
                case .poweredOff:
                    NoticeView(
                        symbol: "bolt.slash.fill",
                        title: "Bluetooth is off",
                        message: "Turn on Bluetooth in the Settings app on your watch."
                    )
                case .unauthorized:
                    NoticeView(
                        symbol: "hand.raised.fill",
                        title: "Bluetooth not allowed",
                        message: "Allow Bluetooth for Pokit under Settings › Privacy & Security › Bluetooth."
                    )
                case .unsupported:
                    NoticeView(
                        symbol: "exclamationmark.triangle.fill",
                        title: "Not supported",
                        message: "This watch cannot connect to Bluetooth accessories."
                    )
                case .unknown, .ready:
                    if pokit.device != nil {
                        MeterView(meter: pokit.meter)
                    } else {
                        DeviceListView()
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .device:
                    DeviceView()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                pokit.setAppActive(true)
            case .background:
                pokit.setAppActive(false)
            default:
                // Inactive is the wrist-down, always-on state: keep measuring.
                break
            }
        }
        .onChange(of: pokit.device == nil) { _, _ in
            path.removeAll()
        }
    }
}

struct NoticeView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}
