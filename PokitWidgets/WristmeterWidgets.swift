import PokitKit
import SwiftUI
import WidgetKit

/// Complications for the watch face and the Smart Stack.
///
/// They are launchers: the app only talks to the meter while it is on screen, so there is
/// no live value a widget could show. Their job is to make the app one tap away, either
/// as it was left or straight into a particular mode.
@main
struct WristmeterWidgets: WidgetBundle {
    var body: some Widget {
        LauncherWidget()
        DCVoltageWidget()
        ContinuityWidget()
    }
}

/// Opens the app in whatever mode it was in.
struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WristmeterLauncher", provider: LauncherProvider()) { _ in
            LauncherView(mode: nil)
        }
        .configurationDisplayName("Wristmeter")
        .description("Opens the multimeter.")
        .supportedFamilies(LauncherView.families)
    }
}

struct DCVoltageWidget: Widget {
    var body: some WidgetConfiguration {
        QuickStart.configuration(kind: "WristmeterDCVoltage", mode: .dcVoltage)
    }
}

struct ContinuityWidget: Widget {
    var body: some WidgetConfiguration {
        QuickStart.configuration(kind: "WristmeterContinuity", mode: .continuity)
    }
}

/// A complication that opens the app in `mode`. To offer another mode, add a widget like
/// the ones above, list it in the bundle and translate the mode's title in this target.
private enum QuickStart {
    static func configuration(kind: String, mode: MultimeterMode) -> some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            LauncherView(mode: mode)
        }
        .configurationDisplayName(LocalizedStringKey(mode.title))
        .description("Opens Wristmeter in this mode.")
        .supportedFamilies(LauncherView.families)
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
    static let families: [WidgetFamily] = [
        .accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular,
    ]

    /// The mode to open the app in; `nil` leaves the app as it was.
    let mode: MultimeterMode?

    @Environment(\.widgetFamily) private var family

    private let symbol = "waveform.path.ecg"

    private var title: LocalizedStringKey {
        mode.map { LocalizedStringKey($0.title) } ?? "Wristmeter"
    }

    var body: some View {
        content
            // Without a URL a tap simply opens the app.
            .widgetURL(mode.flatMap { QuickStartLink.url(for: $0) })
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Label(title, systemImage: symbol)
        case .accessoryCorner:
            cornerMark
                .widgetAccentable()
                .widgetLabel {
                    Text(title)
                }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                GaugeGlyph(notation: mode?.symbol, fallbackSymbol: symbol)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .widgetAccentable()
                    if mode == nil {
                        Text("Tap to measure")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Wristmeter")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            GaugeGlyph(notation: mode?.symbol, fallbackSymbol: symbol)
                .padding(2)
        }
    }

    @ViewBuilder
    private var cornerMark: some View {
        if let mode {
            Text(verbatim: mode.symbol)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        } else {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
        }
    }
}

/// The app icon's motif, an open gauge arc. Inside it either a mode in multimeter notation
/// ("V⎓") or the icon's waveform.
private struct GaugeGlyph: View {
    let notation: String?
    let fallbackSymbol: String

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(135))
                .opacity(0.45)
                .padding(2)
            if let notation {
                Text(verbatim: notation)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .widgetAccentable()
    }
}
