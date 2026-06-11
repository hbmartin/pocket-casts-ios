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
}
