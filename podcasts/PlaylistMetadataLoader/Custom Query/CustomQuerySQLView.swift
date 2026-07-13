import PocketCastsUtils
import SwiftUI
import UIKit

/// SQL mode: an editable monospace WHERE-clause editor, explicit Validate step
/// (save stays disabled until the fragment validates), inline themed errors and
/// live match count, plus the schema-reference sheet and rule seeding.
struct CustomQuerySQLView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var viewModel: CustomPlaylistEditorViewModel

    @State private var showingSchemaReference = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CustomQuerySQLTextEditor(
                    text: $viewModel.sqlText,
                    textColor: UIColor(AppTheme.color(for: .primaryText01, theme: theme))
                )
                .frame(minHeight: 160)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.color(for: .primaryUi02, theme: theme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )

                Text(L10n.playlistCustomSqlHint)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                    .fixedSize(horizontal: false, vertical: true)

                validateRow
                statusView

                HStack(spacing: 24) {
                    Button(L10n.playlistCustomStartFromRules) {
                        viewModel.seedFromCurrentRules()
                    }
                    Button(L10n.playlistCustomSchemaReference) {
                        showingSchemaReference = true
                    }
                }
                .font(.subheadline.weight(.medium))
                .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
            }
            .padding(16)
        }
        .sheet(isPresented: $showingSchemaReference) {
            CustomQuerySchemaReferenceView()
                .environmentObject(theme)
        }
    }

    private var borderColor: Color {
        if case .invalid = viewModel.sqlValidation {
            return AppTheme.color(for: .support05, theme: theme)
        }
        return AppTheme.color(for: .primaryUi05, theme: theme)
    }

    private var validateRow: some View {
        Button {
            viewModel.validateSQL()
        } label: {
            Text(L10n.playlistCustomValidateButton)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(AppTheme.color(for: .primaryInteractive01, theme: theme))
                )
                .foregroundStyle(AppTheme.color(for: .primaryInteractive02, theme: theme))
        }
        .disabled(viewModel.sqlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.sqlValidation == .validating)
    }

    @ViewBuilder private var statusView: some View {
        switch viewModel.sqlValidation {
        case .notValidated:
            Text(L10n.playlistCustomValidationNeeded)
                .font(.footnote)
                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
        case .validating:
            HStack(spacing: 8) {
                ProgressView()
                Text(L10n.playlistCustomValidating)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            }
        case .valid(let matchCount):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text(matchCountText(matchCount))
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.color(for: .support02, theme: theme))
        case .invalid(let message):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.color(for: .support05, theme: theme))
        }
    }

    private func matchCountText(_ count: Int) -> String {
        count == 1
            ? L10n.playlistCustomMatchCountSingular(count.localized(.decimal))
            : L10n.playlistCustomMatchCountPlural(count.localized(.decimal))
    }
}

/// Editable monospace `UITextView` wrapper. All the "smart" input systems are
/// switched off: smart quotes turn `'history'` into typographic quotes that
/// silently break SQL, and autocorrect/autocapitalization mangle identifiers.
struct CustomQuerySQLTextEditor: UIViewRepresentable {
    @Binding var text: String
    let textColor: UIColor

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.keyboardType = .asciiCapable
        textView.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = textColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
