import SwiftUI

@main
struct PokitWatchApp: App {
    @StateObject private var pokit = PokitCentral()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(pokit)
        }
    }
}
