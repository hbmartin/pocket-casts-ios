import Foundation

/// Owns a typed-notification observation token and deregisters it when the
/// owner deallocates.
///
/// Exists because generic `UIHostingController` subclasses cannot declare the
/// `isolated deinit` that token teardown needs: the SDK class is
/// `@preconcurrency @MainActor`, and the compiler propagates that attribute
/// onto an overriding `isolated deinit`, then rejects it ("'@preconcurrency'
/// attribute cannot be applied to this declaration"). Holding the token in
/// this non-generic box gives those controllers deterministic teardown with
/// no deinit of their own.
@MainActor
final class ObservationTokenBox {
    var token: NotificationCenter.ObservationToken? {
        get { tokens.first }
        set { tokens = newValue.map { [$0] } ?? [] }
    }

    var tokens: [NotificationCenter.ObservationToken] = []

    // isolated deinit: reads the isolated token storage to deregister the
    // observations exactly once, on the main actor, when the owner deallocates.
    isolated deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
