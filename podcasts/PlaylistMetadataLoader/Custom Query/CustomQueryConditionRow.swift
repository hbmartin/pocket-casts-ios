import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

/// One condition in the builder: a field menu (driven by the engine's field
/// catalog), an operator menu filtered to the field's allowed operators, and a
/// typed value editor matching the field kind + operator.
struct CustomQueryConditionRow: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var viewModel: CustomPlaylistEditorViewModel

    let condition: CustomQueryDraftCondition

    @State private var showingPodcastPicker = false

    private var field: CustomQueryField { condition.field }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                fieldMenu
                operatorMenu
                Spacer(minLength: 0)
                Button {
                    viewModel.removeNode(id: condition.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.color(for: .primaryIcon03, theme: theme))
                }
                .accessibilityLabel(L10n.playlistCustomRemoveRule)
            }

            valueEditor
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.color(for: .primaryUi01, theme: theme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.color(for: condition.isComplete ? .primaryUi05 : .support05, theme: theme), lineWidth: 1)
        )
        .sheet(isPresented: $showingPodcastPicker) {
            CustomQueryPodcastPickerSheet(selectedUuids: selectedValuesBinding)
                .environmentObject(theme)
        }
    }

    // MARK: - Field + operator menus

    private var fieldMenu: some View {
        Menu {
            // Unavailable fields (flag off, FTS5-less device) are hidden from the
            // picker, but a row whose field is already unavailable keeps rendering:
            // hiding it would silently drop the condition on the next save.
            ForEach(CustomQueryField.allCases.filter { $0.isAvailableInBuilder || $0 == field }, id: \.self) { catalogField in
                Button(catalogField.displayName) {
                    viewModel.updateCondition(condition.changingField(to: catalogField))
                }
            }
        } label: {
            menuLabel(field.displayName)
        }
        .accessibilityLabel(L10n.playlistCustomConditionField)
    }

    private var operatorMenu: some View {
        Menu {
            ForEach(field.allowedOperators, id: \.self) { candidate in
                Button(candidate.displayName) {
                    viewModel.updateCondition(condition.changingOperator(to: candidate))
                }
            }
        } label: {
            menuLabel(condition.op.displayName)
        }
        .accessibilityLabel(L10n.playlistCustomConditionOperator)
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .foregroundStyle(AppTheme.color(for: .primaryInteractive01, theme: theme))
    }

    // MARK: - Typed value editors

    @ViewBuilder private var valueEditor: some View {
        switch field.kind {
        case .text:
            textField(L10n.playlistCustomValuePlaceholder, binding: textBinding)
        case .number:
            numberEditor
        case .boolean:
            Toggle(field.displayName, isOn: boolBinding)
                .font(.subheadline)
                .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
        case .date:
            dateEditor
        case .enumeration:
            enumEditor(for: field)
        case .podcastList:
            podcastEditor
        case .transcript:
            VStack(alignment: .leading, spacing: 4) {
                textField(L10n.playlistCustomValuePlaceholder, binding: textBinding)
                if let footnote = field.footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var numberEditor: some View {
        switch condition.op {
        case .isSet, .isNotSet:
            EmptyView()
        case .between:
            HStack(spacing: 8) {
                numberField(L10n.playlistCustomValueMin, binding: numberBinding)
                numberField(L10n.playlistCustomValueMax, binding: secondNumberBinding)
            }
        default:
            numberField(L10n.playlistCustomValuePlaceholder, binding: numberBinding)
        }
    }

    @ViewBuilder private var dateEditor: some View {
        switch condition.op {
        case .isSet, .isNotSet:
            EmptyView()
        case .inLastDays:
            HStack(spacing: 8) {
                numberField(L10n.playlistCustomValueDays, binding: daysBinding)
                    .frame(maxWidth: 100)
                Text(L10n.playlistCustomValueDaysSuffix)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            }
        case .between:
            VStack(alignment: .leading, spacing: 4) {
                DatePicker(L10n.playlistCustomValueStartDate, selection: dateBinding, displayedComponents: .date)
                DatePicker(L10n.playlistCustomValueEndDate, selection: secondDateBinding, displayedComponents: .date)
            }
            .font(.subheadline)
        default:
            DatePicker(L10n.playlistCustomValueDate, selection: dateBinding, displayedComponents: .date)
                .font(.subheadline)
        }
    }

    private func enumEditor(for field: CustomQueryField) -> some View {
        Menu {
            ForEach(field.enumerationValues, id: \.self) { enumerationValue in
                Button {
                    toggleSelectedValue(enumerationValue)
                } label: {
                    if condition.value.selectedValues.contains(enumerationValue) {
                        Label(field.displayName(forEnumerationValue: enumerationValue), systemImage: "checkmark")
                    } else {
                        Text(field.displayName(forEnumerationValue: enumerationValue))
                    }
                }
            }
        } label: {
            menuLabel(enumSummary(for: field))
        }
    }

    private func enumSummary(for field: CustomQueryField) -> String {
        let selected = field.enumerationValues.filter { condition.value.selectedValues.contains($0) }
        guard !selected.isEmpty else { return L10n.playlistCustomValuePlaceholder }
        return selected.map { field.displayName(forEnumerationValue: $0) }.joined(separator: ", ")
    }

    private var podcastEditor: some View {
        Button {
            showingPodcastPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.caption)
                Text(podcastSummary)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
    }

    private var podcastSummary: String {
        let count = condition.value.selectedValues.count
        guard count > 0 else { return L10n.playlistCustomChoosePodcasts }
        return L10n.playlistCustomPodcastsSelected(count.localized(.decimal))
    }

    // MARK: - Field helpers

    private func textField(_ placeholder: String, binding: Binding<String>) -> some View {
        TextField(placeholder, text: binding)
            .font(.subheadline)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }

    private func numberField(_ placeholder: String, binding: Binding<String>) -> some View {
        TextField(placeholder, text: binding)
            .font(.subheadline)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.decimalPad)
    }

    // MARK: - Value bindings

    private func valueBinding<T>(_ keyPath: WritableKeyPath<CustomQueryDraftValue, T>) -> Binding<T> {
        Binding(
            get: { (viewModel.condition(withID: condition.id) ?? condition).value[keyPath: keyPath] },
            set: { newValue in
                var updated = viewModel.condition(withID: condition.id) ?? condition
                updated.value[keyPath: keyPath] = newValue
                viewModel.updateCondition(updated)
            }
        )
    }

    private var textBinding: Binding<String> { valueBinding(\.text) }
    private var numberBinding: Binding<String> { valueBinding(\.numberText) }
    private var secondNumberBinding: Binding<String> { valueBinding(\.secondNumberText) }
    private var boolBinding: Binding<Bool> { valueBinding(\.boolValue) }
    private var dateBinding: Binding<Date> { valueBinding(\.date) }
    private var secondDateBinding: Binding<Date> { valueBinding(\.secondDate) }
    private var daysBinding: Binding<String> { valueBinding(\.daysText) }
    private var selectedValuesBinding: Binding<[String]> { valueBinding(\.selectedValues) }

    private func toggleSelectedValue(_ value: String) {
        var updated = viewModel.condition(withID: condition.id) ?? condition
        if let index = updated.value.selectedValues.firstIndex(of: value) {
            updated.value.selectedValues.remove(at: index)
        } else {
            updated.value.selectedValues.append(value)
        }
        viewModel.updateCondition(updated)
    }
}

/// Podcast multi-select sheet reusing the folders' `PodcastPickerView`.
struct CustomQueryPodcastPickerSheet: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedUuids: [String]

    @StateObject private var pickerModel = PodcastPickerModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.playlistCustomChoosePodcasts)
                    .font(.headline)
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Button(L10n.done) {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.color(for: .primaryInteractive01, theme: theme))
            }
            .padding(16)

            PodcastPickerView(pickerModel: pickerModel)
        }
        .background(AppTheme.color(for: .primaryUi01, theme: theme))
        .onAppear {
            pickerModel.sortingStrategy = .none
            pickerModel.selectedPodcastUuids = selectedUuids
            pickerModel.setup()
        }
        .onChange(of: pickerModel.selectedPodcastUuids) { _, newValue in
            selectedUuids = newValue
        }
    }
}
