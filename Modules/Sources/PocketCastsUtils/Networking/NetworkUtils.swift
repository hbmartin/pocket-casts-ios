import Foundation
import Network

public final class NetworkUtils: Sendable {

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            switch path.status {
            case .satisfied:
                FileLog.shared.addMessage("NetworkMonitor: Network is connected isExpensive: \(path.isExpensive)")
            case .unsatisfied:
                FileLog.shared.addMessage("NetworkMonitor: Network is disconnected")
            case .requiresConnection:
                FileLog.shared.addMessage("NetworkMonitor: Network requires connection")
            @unknown default:
                FileLog.shared.addMessage("NetworkMonitor: Unknown path status")
            }
        }
        monitor.start(queue: .main)
    }

    deinit {
        monitor.cancel()
    }

    public static let shared = NetworkUtils()

    // MARK: - Connectivity

    public func isConnectedToUnexpensiveConnection() -> Bool {
        let path = monitor.currentPath
        return Self.isUnexpensive(status: path.status, isExpensive: path.isExpensive)
    }

    static func isUnexpensive(status: NWPath.Status, isExpensive: Bool) -> Bool {
        guard case .satisfied = status else { return false }
        return !isExpensive
    }

    public func isConnected() -> Bool {
        monitor.currentPath.status == .satisfied
    }
}
