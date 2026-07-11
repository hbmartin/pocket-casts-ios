import SwiftUI

/// A titled slider row with a live monospaced value readout, themed for
/// settings lists.
struct TuningSliderRow: View {
    @EnvironmentObject private var theme: Theme

    let title: String
    let range: ClosedRange<Double>
    let step: Double
    var unit: String = ""
    var fractionDigits: Int = 1
    @Binding var value: Double

    private var formattedValue: String {
        let number = String(format: "%.\(fractionDigits)f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Text(formattedValue)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
            Slider(value: $value, in: range, step: step)
                .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
        .padding(.vertical, 2)
    }
}

/// A themed toggle row.
struct TuningToggleRow: View {
    @EnvironmentObject private var theme: Theme

    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
        }
        .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
    }
}

/// A themed menu-style picker row over a fixed option set.
struct TuningPickerRow<Value: Hashable>: View {
    @EnvironmentObject private var theme: Theme

    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        Picker(selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        } label: {
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
        }
        .pickerStyle(.menu)
        .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
    }
}

/// A destructive-styled reset button row.
struct TuningResetButton: View {
    @EnvironmentObject private var theme: Theme

    let title: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppTheme.color(for: .support05, theme: theme))
        }
    }
}

/// A static label/value row for the live meter readouts.
struct TuningMeterRow: View {
    @EnvironmentObject private var theme: Theme

    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
    }
}
