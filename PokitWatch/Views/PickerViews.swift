import PokitKit
import SwiftUI

/// Sheet with the measurement modes of the connected product, and the device's two other
/// functions. It is the one place to switch between them.
struct ModePickerView: View {
    @EnvironmentObject private var pokit: PokitCentral
    @Environment(\.dismiss) private var dismiss

    private var modes: [MultimeterMode] {
        (pokit.device?.product ?? .meter).measurementModes
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(modes, id: \.self) { mode in
                        Button {
                            pokit.select(mode: mode)
                            dismiss()
                        } label: {
                            HStack {
                                Text(verbatim: mode.symbol)
                                    .font(.headline)
                                    .frame(width: 46, alignment: .leading)
                                Text(LocalizedStringKey(mode.title))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 2)
                                if mode == pokit.mode, pokit.tool == .meter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .foregroundStyle(isExpected(mode) ? Color.primary : Color.secondary)
                        }
                    }
                } footer: {
                    if pokit.status?.switchPosition != nil {
                        Text("Greyed-out modes need a different position of the switch on the Pokit.")
                    }
                }
                Section {
                    toolRow(.scope, symbol: "waveform.path.ecg", title: "Oscilloscope")
                    toolRow(.logger, symbol: "chart.xyaxis.line", title: "Data Logger")
                }
            }
            .navigationTitle("Mode")
        }
    }

    private func isExpected(_ mode: MultimeterMode) -> Bool {
        pokit.status?.switchPosition?.isExpectedToSupport(mode) ?? true
    }

    private func toolRow(_ tool: Tool, symbol: String, title: LocalizedStringKey) -> some View {
        Button {
            pokit.open(tool)
            dismiss()
        } label: {
            HStack {
                Image(systemName: symbol)
                    .frame(width: 46, alignment: .leading)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if pokit.tool == tool {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}

/// Sheet with "Auto" and the fixed ranges of the current mode.
struct RangePickerView: View {
    @EnvironmentObject private var pokit: PokitCentral
    @Environment(\.dismiss) private var dismiss

    private var ranges: [MeterRange] {
        (pokit.device?.product ?? .meter).ranges(for: pokit.mode)
    }

    var body: some View {
        NavigationStack {
            List {
                row(title: Text("Automatic"), selection: .auto)
                ForEach(ranges) { range in
                    row(title: Text(verbatim: range.label(unit: pokit.mode.unit)), selection: .fixed(range.index))
                }
            }
            .navigationTitle("Range")
        }
    }

    private func row(title: Text, selection: RangeSelection) -> some View {
        Button {
            pokit.select(range: selection)
            dismiss()
        } label: {
            HStack {
                title
                Spacer(minLength: 2)
                if selection == pokit.range {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
