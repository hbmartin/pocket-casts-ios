import Foundation

protocol DispatchQueueing: AnyObject {
    func async(execute work: @escaping @Sendable @convention(block) () -> Void)
}

extension DispatchQueue: DispatchQueueing {
    func async(execute work: @escaping @Sendable @convention(block) () -> Void) {
        async(group: nil, qos: qos, flags: [], execute: work)
    }
}
