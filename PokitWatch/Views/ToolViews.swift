import PokitKit
import SwiftUI
import WatchKit

/// Toolbar link to the device page, showing the battery when it is known.
struct DeviceLink: View {
    @EnvironmentObject private var pokit: PokitCentral

    var body: some View {
        NavigationLink(value: Route.device) {
            Image(systemName: batterySymbol)
        }
        .accessibilityLabel(Text("Device"))
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
}

/// The line at the top of the oscilloscope and logger screens. Like the meter's mode line
/// it opens the list of modes, which is where one switches between the three.
struct ToolSwitcher: View {
    @EnvironmentObject private var pokit: PokitCentral
    let symbol: String
    let title: LocalizedStringKey
    @State private var showsModes = false

    var body: some View {
        Button {
            showsModes = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                Text(title)
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
        .sheet(isPresented: $showsModes) {
            ModePickerView()
                .environmentObject(pokit)
        }
    }
}

/// A line plot of samples, scaled to fill its frame.
struct WaveformView: View {
    let values: [Double]
    var tint: Color = .yellow

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for step in 1..<4 {
                let x = size.width * CGFloat(step) / 4
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            grid.move(to: CGPoint(x: 0, y: size.height / 2))
            grid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(grid, with: .color(.gray.opacity(0.35)), lineWidth: 0.5)

            let finite = values.filter(\.isFinite)
            guard finite.count > 1, let low = finite.min(), let high = finite.max() else { return }
            // A flat signal gets a band around it rather than a line glued to an edge, and
            // noise on a steady level is not blown up to full height.
            let smallestSpan = max(abs(high), abs(low)) * 0.02
            let span = max(high - low, smallestSpan, 1e-9) * 1.15
            let middle = (high + low) / 2
            let bottom = middle - span / 2

            func y(for value: Double) -> CGFloat {
                size.height * CGFloat(1 - (value - bottom) / span)
            }

            if bottom < 0, bottom + span > 0 {
                var zero = Path()
                zero.move(to: CGPoint(x: 0, y: y(for: 0)))
                zero.addLine(to: CGPoint(x: size.width, y: y(for: 0)))
                context.stroke(zero, with: .color(.gray), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            }

            var line = Path()
            let lastIndex = CGFloat(finite.count - 1)
            for (index, value) in finite.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(index) / lastIndex, y: y(for: value))
                if index == 0 {
                    line.move(to: point)
                } else {
                    line.addLine(to: point)
                }
            }
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

// MARK: - Oscilloscope

/// The oscilloscope screen: the waveform, what it measures, and run/hold.
struct ScopeView: View {
    @EnvironmentObject private var pokit: PokitCentral
    @ObservedObject var scope: ScopeState
    @State private var showsSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ToolSwitcher(symbol: "waveform.path.ecg", title: "Oscilloscope")
            if pokit.phase == .ready {
                WaveformView(values: scope.capture?.values ?? [], tint: scope.isRunning ? .yellow : .orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        pokit.toggleScopeRunning()
                    }
                infoLine
                    .padding(.top, 2)
                controls
                    .padding(.top, 5)
                    .padding(.horizontal, isCompact ? 10 : 16)
            } else {
                Spacer(minLength: 0)
                ConnectionStatusView()
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Same arrangement as the meter: the controls sit in the bottom safe area.
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                DeviceLink()
            }
        }
        .sheet(isPresented: $showsSettings) {
            ScopeSettingsView(scope: scope)
                .environmentObject(pokit)
        }
    }

    /// One line under the waveform: a problem, what the oscilloscope is waiting for, or
    /// what the capture measures.
    private var infoLine: some View {
        Group {
            if scope.activity == .failed {
                Label("Capture failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let capture = scope.capture, let summary = capture.summary {
                Text(verbatim: summaryText(summary, mode: capture.mode))
                    .foregroundStyle(scope.isRunning ? Color.secondary : Color.orange)
            } else if scope.trigger != .off {
                Text("Waiting for trigger…")
                    .foregroundStyle(.secondary)
            } else {
                Text("Capturing…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                showsSettings = true
            } label: {
                Text(verbatim: "\(scope.mode.symbol) · \(ScopeState.label(forWindow: scope.window))")
            }
            .buttonStyle(PillButtonStyle())
            Button {
                pokit.toggleScopeRunning()
            } label: {
                Image(systemName: scope.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(PillButtonStyle(tint: scope.isRunning ? .white : .orange))
            .frame(maxWidth: isCompact ? 40 : 52)
            .accessibilityLabel(Text("Hold"))
        }
    }

    private var isCompact: Bool {
        WKInterfaceDevice.current().screenBounds.width < 180
    }

    /// A repeating signal is described by its swing and frequency, anything else by its
    /// extremes.
    private func summaryText(_ summary: WaveformSummary, mode: MultimeterMode) -> String {
        if let frequency = summary.frequency {
            let swing = MeterDisplay.format(summary.peakToPeak, mode: mode).text
            let rate = ValueFormatter.format(frequency, unit: "Hz", digits: 3, minimum: .none).text
            return "↕ \(swing)   \(rate)"
        }
        let low = MeterDisplay.format(summary.minimum, mode: mode).text
        let high = MeterDisplay.format(summary.maximum, mode: mode).text
        return "↓ \(low)   ↑ \(high)"
    }
}

/// Sheet with what the oscilloscope captures: signal, range, time span and trigger.
struct ScopeSettingsView: View {
    @EnvironmentObject private var pokit: PokitCentral
    @ObservedObject var scope: ScopeState

    private var ranges: [MeterRange] {
        (pokit.device?.product ?? .meter).ranges(for: scope.mode)
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Signal", selection: Binding(get: { scope.mode }, set: { pokit.setScope(mode: $0) })) {
                    ForEach(ScopeSettings.modes, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode)
                    }
                }
                Picker("Range", selection: Binding(get: { scope.range }, set: { pokit.setScope(range: $0) })) {
                    Text("Automatic").tag(RangeSelection.auto)
                    ForEach(ranges) { range in
                        Text(verbatim: range.label(unit: scope.mode.unit)).tag(RangeSelection.fixed(range.index))
                    }
                }
                Picker("Time span", selection: Binding(get: { scope.window }, set: { pokit.setScope(window: $0) })) {
                    ForEach(ScopeState.windows, id: \.self) { window in
                        Text(verbatim: ScopeState.label(forWindow: window)).tag(window)
                    }
                }
                Picker("Trigger", selection: Binding(get: { scope.trigger }, set: { pokit.setScope(trigger: $0) })) {
                    Text("Off").tag(ScopeTriggerKind.off)
                    Text("Rising edge").tag(ScopeTriggerKind.rising)
                    Text("Falling edge").tag(ScopeTriggerKind.falling)
                }
            }
            .pickerStyle(.navigationLink)
            .navigationTitle("Oscilloscope")
        }
    }
}

// MARK: - Data logger

/// The data logger screen: set up and start a recording, watch one that is running, and
/// look at what was recorded.
struct LoggerView: View {
    @EnvironmentObject private var pokit: PokitCentral
    @ObservedObject var logger: LoggerState

    private var ranges: [MeterRange] {
        (pokit.device?.product ?? .meter).ranges(for: logger.mode.multimeterMode)
    }

    var body: some View {
        List {
            if !logger.isSampling {
                ToolSwitcher(symbol: "chart.xyaxis.line", title: "Data Logger")
                    .listRowBackground(Color.clear)
            }
            if pokit.phase != .ready {
                ConnectionStatusView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if logger.isSampling {
                runningSection
            } else {
                setupSection
            }
            if let log = logger.log {
                dataSection(log)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                DeviceLink()
            }
        }
    }

    private var runningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Label("Logging", systemImage: "record.circle")
                    .font(.headline)
                    .foregroundStyle(.red)
                if let metadata = logger.metadata {
                    Text(verbatim: description(of: metadata))
                    Text("\(metadata.sampleCount) samples")
                        .foregroundStyle(.secondary)
                    if let start = metadata.startDate {
                        Text(start, format: .dateTime.day().month().hour().minute())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            fetchButton
            Button("Stop", role: .destructive) {
                pokit.stopLogger()
            }
        } footer: {
            Text("Logging continues on the Pokit when you leave the app. Stop it to measure again.")
        }
    }

    private var setupSection: some View {
        Section {
            Picker("Quantity", selection: Binding(get: { logger.mode }, set: { pokit.setLogger(mode: $0) })) {
                ForEach(LoggerMode.allCases, id: \.self) { mode in
                    Text(LocalizedStringKey(mode.multimeterMode.title)).tag(mode)
                }
            }
            if let highest = ranges.last {
                Picker(
                    "Range",
                    selection: Binding(get: { logger.rangeIndex ?? highest.index }, set: { pokit.setLogger(rangeIndex: $0) })
                ) {
                    ForEach(ranges) { range in
                        Text(verbatim: range.label(unit: logger.mode.multimeterMode.unit)).tag(range.index)
                    }
                }
            }
            Picker("Interval", selection: Binding(get: { logger.interval }, set: { pokit.setLogger(interval: $0) })) {
                ForEach(LoggerState.intervals, id: \.self) { interval in
                    Text(verbatim: LoggerState.label(forInterval: Double(interval))).tag(interval)
                }
            }
            Button("Start logging") {
                pokit.startLogger()
            }
            if logger.startWasRejected {
                Label("Could not start", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if (logger.metadata?.sampleCount ?? 0) > 0, logger.log == nil {
                fetchButton
            }
        }
        .pickerStyle(.navigationLink)
    }

    private var fetchButton: some View {
        Button {
            pokit.fetchLog()
        } label: {
            HStack {
                Text("Load data")
                Spacer(minLength: 2)
                if logger.isFetching {
                    ProgressView()
                        .frame(width: 20)
                }
            }
        }
        .disabled(logger.isFetching)
    }

    @ViewBuilder
    private func dataSection(_ log: LoggedData) -> some View {
        Section("Recorded data") {
            if log.values.isEmpty {
                Text("No samples yet")
                    .foregroundStyle(.secondary)
            } else {
                WaveformView(values: log.values, tint: .green)
                    .frame(height: 64)
                LabeledContent("Samples", value: "\(log.values.count)")
                if let summary = log.summary {
                    LabeledContent("Minimum", value: text(summary.minimum, log: log))
                    LabeledContent("Maximum", value: text(summary.maximum, log: log))
                    LabeledContent("Average", value: text(summary.mean, log: log))
                }
                LabeledContent("Interval", value: LoggerState.label(forInterval: log.interval))
                if let start = log.start {
                    LabeledContent("Started") {
                        Text(start, format: .dateTime.day().month().hour().minute())
                    }
                }
            }
        }
    }

    /// `V⎓ · 10 s`
    private func description(of metadata: LoggerMetadata) -> String {
        let symbol = metadata.mode?.multimeterMode.symbol ?? "?"
        return "\(symbol) · \(LoggerState.label(forInterval: metadata.interval))"
    }

    private func text(_ value: Double, log: LoggedData) -> String {
        MeterDisplay.format(value, mode: log.mode?.multimeterMode).text
    }
}
