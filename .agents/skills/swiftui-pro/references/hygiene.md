# Hygiene

- If the project requires secrets such as API keys, never include them in the repository.
- Code comments and documentation comments should be present where the logic isn't self-evident.
- Unit tests should exist for core application logic. UI tests only where unit tests are not possible.
- `@AppStorage` must never be used to store usernames, passwords, or other sensitive data. Use the keychain for that.
- If SwiftLint is configured, it should return no warnings or errors.
- Add user-facing strings to the English `Localizable.strings` file with translator comments, then access them through the generated `L10n` enum, e.g. `L10n.someKey`, using `NSLocalizedString`-backed generated accessors. Do not introduce `LocalizedStringKey` or `Text(.someKey)` workflows in this repo; rely on the existing translation pipeline for other supported languages.
- If the Xcode MCP is configured, prefer its tools over generic alternatives. For example, `RenderPreview` is able to capture images of rendered SwiftUI previews for examination, and `DocumentationSearch` can search Apple’s documentation for latest usage instructions.
