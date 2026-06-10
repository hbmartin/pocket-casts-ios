import Foundation
import PocketCastsUtils

class DataHelper {
    class func run(query: String, values: [Any]?, methodName: String, onQueue: PCDBQueue) {
        onQueue.write { db in
            do {
                try db.executeUpdate(query, values: values)
            } catch {
                FileLog.shared.addMessage("\(methodName) error: \(error)")
            }
        }
    }
}
