import Capture
import Foundation

struct BitdriftAnalyticsAdapter: AnalyticsAdapter {
    func track(name: String, properties: [String: Sendable]) async {
        var fields: Fields = ["event_name": name]
        properties.forEach { property in
            fields["property_\(property.key)"] = String(describing: property.value)
        }

        Logger.logInfo("Analytics event", fields: fields)
    }
}
