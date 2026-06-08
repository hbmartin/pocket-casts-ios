import Foundation
import TelemetryDeck

struct TelemetryDeckAnalyticsAdapter: AnalyticsAdapter {
    func track(name: String, properties: [String: Sendable]) async {
        let parameters = properties.reduce(into: [String: String]()) { result, property in
            result[property.key] = String(describing: property.value)
        }

        TelemetryDeck.signal(name, parameters: parameters)
    }
}
