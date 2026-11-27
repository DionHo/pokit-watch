import PokitKit
import SwiftUI

enum Route: Hashable {
    case device
    case diagnostics
}

/// Decides which top-level screen is shown: a Bluetooth problem, the device list, or the
/// tool in use (meter, oscilloscope or data logger). Once a device is remembered the tool's
/// screen stays up, also while the connection is being (re-)established.
struct RootView: View {
    @EnvironmentObject private var pokit: PokitCentral
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] =
        UserDefaults.standard.string(forKey: "PokitDemoScreen") == "device" ? [.device] : []

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
                        message: "Allow Bluetooth for Wristmeter under Settings › Privacy & Security › Bluetooth."
                    )
                case .unsupported:
                    NoticeView(
                        symbol: "exclamationmark.triangle.fill",
                        title: "Not supported",
                        message: "This watch cannot connect to Bluetooth accessories."
                    )
                case .unknown, .ready:
                    if pokit.device == nil {
                        DeviceListView()
                    } else {
                        switch pokit.tool {
                        case .meter:
                            MeterView(meter: pokit.meter)
                        case .scope:
                            ScopeView(scope: pokit.scope)
                        case .logger:
                            LoggerView(logger: pokit.logger)
                        }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .device:
                    DeviceView()
                case .diagnostics:
                    DiagnosticsView(log: pokit.diagnostics)
                }
            }
        }
        // `initial` covers a launch that never reaches the screen.
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            switch newPhase {
            case .active:
                pokit.setAppActive(true)
            case .background:
                // Off screen: the meter is disconnected until the app is back.
                pokit.setAppActive(false)
            default:
                // Inactive is the wrist-down, always-on state. The app is still shown
                // (dimmed), so keep measuring; it also passes through here on its way to
                // or from the background, which must not change anything.
                break
            }
        }
        .onChange(of: pokit.device == nil) { _, _ in
            path.removeAll()
        }
        // A quick-start complication was tapped.
        .onOpenURL { url in
            guard let mode = QuickStartLink.mode(from: url) else { return }
            path.removeAll()
            // Already measuring in that mode: leave hold and min/max alone. With no device
            // chosen yet the mode is kept for when one is.
            let isCurrent = pokit.tool == .meter && pokit.mode == mode
            if !isCurrent, pokit.device?.product.measurementModes.contains(mode) != false {
                pokit.select(mode: mode)
            }
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
