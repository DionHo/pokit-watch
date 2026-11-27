import Foundation
import PokitKit

/// What the app is using the device for. The device does one of these at a time.
enum Tool: Equatable {
    case meter
    case scope
    case logger
}

// MARK: - Oscilloscope

/// A finished oscilloscope capture, ready to draw.
struct ScopeCapture: Equatable {
    /// Samples in base units (V or A).
    var values: [Double]
    /// Samples per second.
    var sampleRate: Double
    var mode: MultimeterMode
    var range: MeterRange?
    var summary: WaveformSummary?
}

enum ScopeTriggerKind: Hashable {
    /// Capture right away, again and again.
    case off
    case rising
    case falling
}

enum ScopeActivity: Equatable {
    /// Nothing requested (hold).
    case idle
    /// A capture was requested; the device is sampling or waiting for its trigger.
    case waiting
    /// Samples are coming in.
    case receiving
    case failed
}

/// The oscilloscope's settings and its latest capture. Like `MeterState` it is kept apart
/// from `PokitCentral` so that only the oscilloscope screen redraws with every capture.
/// Views read it; changes go through `PokitCentral`, which has to tell the device.
final class ScopeState: ObservableObject {
    /// Selectable lengths of a capture, in microseconds.
    static let windows: [UInt32] = [
        1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000, 200_000, 500_000, 1_000_000,
    ]
    /// More samples than the screen has pixels across would only make the transfer slower.
    static let sampleCount: UInt16 = 250

    @Published var mode: MultimeterMode = .dcVoltage
    /// `.auto` is done by the app (the device's oscilloscope has no auto-range).
    @Published var range: RangeSelection = .auto
    @Published var window: UInt32 = 20_000
    @Published var trigger: ScopeTriggerKind = .off
    /// Capture continuously; `false` keeps the last capture on screen.
    @Published var isRunning = true
    @Published var activity: ScopeActivity = .idle
    @Published var capture: ScopeCapture?

    /// `20 ms`, `1 s`
    static func label(forWindow microseconds: UInt32) -> String {
        microseconds >= 1_000_000
            ? "\(microseconds / 1_000_000) s"
            : "\(microseconds / 1_000) ms"
    }
}

// MARK: - Data logger

/// Samples fetched from the device's data logger.
struct LoggedData: Equatable {
    /// Values in base units, oldest first.
    var values: [Double]
    var mode: LoggerMode?
    /// Seconds between samples.
    var interval: Double
    var start: Date?
    var summary: WaveformSummary?
}

/// The data logger's settings, what the device reports about its log, and fetched data.
/// Views read it; changes go through `PokitCentral`.
final class LoggerState: ObservableObject {
    /// Selectable sampling intervals in seconds. Both products can do all of them.
    static let intervals: [UInt32] = [1, 5, 10, 30, 60, 300, 900, 3600]

    @Published var mode: LoggerMode = .dcVoltage
    /// `nil` stands for the highest range, the safe choice for an unattended recording.
    @Published var rangeIndex: UInt8?
    @Published var interval: UInt32 = 10
    /// The device's latest report. `nil` until it has been read after connecting.
    @Published var metadata: LoggerMetadata?
    @Published var log: LoggedData?
    @Published var isFetching = false
    /// The device refused the last start command.
    @Published var startWasRejected = false

    /// The device is recording. While it is, the app leaves the device alone apart from
    /// stopping the log or fetching what is there.
    var isSampling: Bool {
        metadata?.status == .sampling
    }

    /// `10 s`, `5 min`, `1 h`
    static func label(forInterval seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        if whole >= 3600, whole % 3600 == 0 { return "\(whole / 3600) h" }
        if whole >= 60, whole % 60 == 0 { return "\(whole / 60) min" }
        return "\(whole) s"
    }
}
