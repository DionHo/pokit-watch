import Foundation

/// A short rolling record of what happened on the Bluetooth link.
///
/// There is no way to read logs from the watch without Xcode. This list can be opened on
/// the watch itself (device page), so that a screenshot shows what the app sent and what
/// the device answered when something does not work.
final class DiagnosticsLog: ObservableObject {
    struct Entry: Identifiable {
        let id: Int
        let time: Date
        let text: String
    }

    private static let capacity = 80

    @Published private(set) var entries: [Entry] = []
    private var counter = 0

    func add(_ text: String) {
        counter += 1
        entries.append(Entry(id: counter, time: Date(), text: text))
        if entries.count > DiagnosticsLog.capacity {
            entries.removeFirst(entries.count - DiagnosticsLog.capacity)
        }
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
