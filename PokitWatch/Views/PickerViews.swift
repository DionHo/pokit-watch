import PokitKit
import SwiftUI

/// Sheet with the measurement modes of the connected product.
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
                                if mode == pokit.mode {
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
            }
            .navigationTitle("Mode")
        }
    }

    private func isExpected(_ mode: MultimeterMode) -> Bool {
        pokit.status?.switchPosition?.isExpectedToSupport(mode) ?? true
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
