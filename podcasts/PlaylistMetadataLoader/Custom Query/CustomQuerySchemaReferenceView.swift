import PocketCastsDataModel
import SwiftUI

/// Schema-reference sheet for SQL mode: every catalog field as a
/// column / type / example row, so users never have to guess identifiers.
struct CustomQuerySchemaReferenceView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.playlistCustomSchemaReference)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.playlistCustomSchemaDescription)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(CustomQueryField.allCases, id: \.self) { field in
                        fieldRow(field)
                    }
                }
                .padding(16)
            }
        }
        .background(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    private func fieldRow(_ field: CustomQueryField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(field.columnExpression)
                    .font(.footnote.monospaced().weight(.semibold))
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Text(field.kindDisplayName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            }
            Text(field.displayName)
                .font(.caption)
                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            Text(field.exampleFragment)
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.color(for: .support01, theme: theme))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.color(for: .primaryUi02, theme: theme))
        )
    }
}
