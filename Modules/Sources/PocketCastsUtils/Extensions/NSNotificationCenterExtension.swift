import Foundation

public extension NotificationCenter {
    static func postOnMainThread(notification: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: notification, object: object, userInfo: userInfo)
            return
        }

        // Force the notification to be posted on the main thread. The payload is handed over
        // wholesale via an unchecked wrapper; the dispatching thread does not touch it afterwards.
        let payload = UncheckedSendable((object, userInfo))
        DispatchQueue.main.sync {
            NotificationCenter.default.post(name: notification, object: payload.value.0, userInfo: payload.value.1)
        }
    }

    /// Typed-message counterpart of `postOnMainThread(notification:object:userInfo:)`,
    /// preserving its blocking main-sync delivery semantics exactly (posters may rely on
    /// observers having run when the call returns). A `MainActorMessage` bridges
    /// bidirectionally with string-based posts/observers on the same `Notification.Name`,
    /// so posters and observers migrate independently. Messages must be Sendable value
    /// types — they cross from the posting thread to the main actor.
    static func postOnMainThread<M: NotificationCenter.MainActorMessage & Sendable>(_ message: M) {
        // Post the bridged legacy Notification rather than the message itself: the SDK's
        // typed post(_:) invokes makeNotification but discards its object/userInfo when
        // delivering to string-based observers (probe-verified on the 26.5 SDK), which
        // would silently break every unconverted observer reading the frozen payload
        // shape. A legacy post still reaches typed observers — they rebuild the message
        // via makeMessage.
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                NotificationCenter.default.post(M.makeNotification(message))
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    NotificationCenter.default.post(M.makeNotification(message))
                }
            }
        }
    }
}

/// Boilerplate reducer for the legacy notifications whose payload is an episode or
/// podcast uuid carried in `Notification.object`. Conformers supply `name` and get the
/// bridged `makeMessage`/`makeNotification` pair for free — the bridged representation
/// (uuid in `object`) is frozen during the migration so unconverted string-based
/// observers keep working.
public protocol UuidBridgedMessage: NotificationCenter.MainActorMessage where Subject == AnyObject {
    var uuid: String? { get }
    init(uuid: String?)
}

public extension UuidBridgedMessage {
    static func makeMessage(_ notification: Notification) -> Self? {
        Self(uuid: notification.object as? String)
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: message.uuid, userInfo: nil)
    }
}
