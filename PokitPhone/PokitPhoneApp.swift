import SwiftUI

/// The iPhone side is only a container: App Store Connect and TestFlight deliver the
/// watch app inside an iOS app. Everything real happens in the watch app, which talks
/// to the meter on its own.
@main
struct PokitPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            HostInfoView()
        }
    }
}

struct HostInfoView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .padding(.top, 48)

                Text("Wristmeter")
                    .font(.largeTitle.bold())

                Text("This app runs on your Apple Watch. It connects to a Pokit Meter or Pokit Pro directly from the watch, so the iPhone is not needed while measuring.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    Label("Open the Watch app on this iPhone and install “Wristmeter” under Available Apps if it is not on your watch yet.", systemImage: "1.circle.fill")
                    Label("Start Wristmeter on the watch and switch your meter on.", systemImage: "2.circle.fill")
                    Label("Pick the meter from the list. The watch remembers it and reconnects on its own next time.", systemImage: "3.circle.fill")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))

                Text("Version \(version)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)

                Text("Unofficial project, not affiliated with Pokit Innovations.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }
}

#Preview {
    HostInfoView()
}
