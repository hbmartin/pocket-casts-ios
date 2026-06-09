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
    /// Detecting the placeholder *shape* — rather than comparing against a specific
    /// literal — keeps this correct even if a token in `ApiCredentials.tpl` is renamed.
    var isMissingOrPlaceholderCredential: Bool {
        isEmpty || (hasPrefix("%{") && hasSuffix("}"))
    }
}
