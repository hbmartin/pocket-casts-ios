extension String {
    /// `true` when this credential value is missing or still an un-substituted
    /// build-time placeholder of the form `%{token}` (for example the TelemetryDeck
    /// App ID token).
    ///
    /// Credentials are injected by `replace_secrets.rb` from `ApiCredentials.tpl`.
    /// Builds without secrets leave the value empty (the external-contributor `sed`
    /// strips placeholders) or as the raw `%{token}` placeholder. Either way the value
    /// must not be handed to an SDK, so callers should skip initialization.
    ///
    /// This is a conservative heuristic: any value exactly shaped like `%{...}` is
    /// treated as unresolved so renamed template tokens are still caught.
    var isMissingOrPlaceholderCredential: Bool {
        isEmpty || (hasPrefix("%{") && hasSuffix("}"))
    }
}
