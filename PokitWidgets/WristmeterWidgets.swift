import SwiftUI
import WidgetKit

/// Complications for the watch face and the Smart Stack.
///
/// They are launchers: the app only talks to the meter while it is on screen, so there is
/// no live value a widget could show. Their job is to make the app one tap away.
@main
struct WristmeterWidgets: WidgetBundle {
    var body: some Widget {
        LauncherWidget()
    }
}

struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WristmeterLauncher", provider: LauncherProvider()) { _ in
            LauncherView()
        }
        .configurationDisplayName("Wristmeter")
        .description("Opens the multimeter.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct LauncherEntry: TimelineEntry {
    let date: Date
}

/// The content never changes, so one entry is enough.
struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: Date())], policy: .never))
    }
}

struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    private let symbol = "waveform.path.ecg"

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Label("Wristmeter", systemImage: symbol)
        case .accessoryCorner:
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .widgetAccentable()
                .widgetLabel {
                    Text("Wristmeter")
                }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                GaugeGlyph(symbol: symbol)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wristmeter")
                        .font(.headline)
                        .widgetAccentable()
                    Text("Tap to measure")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            GaugeGlyph(symbol: symbol)
                .padding(2)
        }
    }
}

/// The app icon's motif: an open gauge arc around a waveform.
private struct GaugeGlyph: View {
    let symbol: String

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(135))
                .opacity(0.45)
                .padding(2)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
        }
        .widgetAccentable()
    }
}
