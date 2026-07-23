import Foundation
import MetricKit
import PocketCastsUtils

/// Receives MetricKit's daily metric payloads and crash/hang diagnostic payloads,
/// persists the raw JSON to a local ring buffer (viewable from the Beta menu),
/// and surfaces scalar summaries through the analytics adapter fan-out — which
/// already honors the user's analytics opt-out. No third-party SDK involved.
/// @unchecked Sendable: stateless (no stored properties); unchecked only because the NSObject superclass blocks a checked conformance.
nonisolated final class MetricKitCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitCollector()

    /// Ring-buffer directory beside the debug logs (`Documents/metrickit`).
    static var payloadDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/metrickit", isDirectory: true)
    }

    private static let maxStoredPayloads = 40

    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: - MXMetricManagerSubscriber (delivered on a background queue)

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            persist(payload.jsonRepresentation(), prefix: "metrics")
            trackSummary(of: payload)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            persist(payload.jsonRepresentation(), prefix: "diagnostics")
            trackSummary(of: payload)
        }
    }

    // MARK: - Ring buffer

    private func persist(_ data: Data, prefix: String) {
        let directory = Self.payloadDirectory
        let name = Self.payloadFilename(prefix: prefix)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            pruneOldPayloads(in: directory)
        } catch {
            FileLog.shared.addMessage("MetricKitCollector: failed to persist payload: \(error)")
        }
    }

    /// Millisecond timestamps preserve lexical age ordering; UTC prevents
    /// timezone changes and DST fallbacks from reversing that order. The full
    /// UUID prevents same-millisecond batches from overwriting one another.
    static func payloadFilename(
        prefix: String,
        date: Date = Date(),
        identifier: UUID = UUID()
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "\(prefix)-\(formatter.string(from: date))-\(identifier.uuidString).json"
    }

    /// Prunes per prefix: one global sort would order "diagnostics-*" before
    /// every "metrics-*" and sacrifice fresh crash diagnostics to keep old metrics.
    private func pruneOldPayloads(in directory: URL) {
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else { return }
        let payloads = urls.map { url in
            let values = try? url.resourceValues(forKeys: resourceKeys)
            return StoredPayload(name: url.lastPathComponent, modificationDate: values?.contentModificationDate)
        }
        for prefix in ["diagnostics-", "metrics-"] {
            for name in Self.payloadNamesToPrune(
                payloads,
                prefix: prefix,
                keepingNewest: Self.maxStoredPayloads
            ) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    struct StoredPayload: Equatable, Sendable {
        let name: String
        let modificationDate: Date?
    }

    /// Ordered oldest-first by an absolute timestamp. Current names carry UTC;
    /// legacy names carry device-local wall time without a timezone, so their
    /// filesystem modification date is the only recoverable absolute instant.
    static func payloadNamesToPrune(
        _ payloads: [StoredPayload],
        prefix: String,
        keepingNewest limit: Int
    ) -> [String] {
        let matching = payloads.filter { $0.name.hasPrefix(prefix) && $0.name.hasSuffix(".json") }
        guard matching.count > limit else { return [] }
        let oldestFirst = matching
            .map { payload in
                (
                    name: payload.name,
                    stamp: Self.stampedDate(
                        in: payload.name,
                        prefix: prefix,
                        legacyModificationDate: payload.modificationDate
                    )
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.stamp, rhs.stamp) {
                case let (lhsStamp?, rhsStamp?):
                    return lhsStamp == rhsStamp ? lhs.name < rhs.name : lhsStamp < rhsStamp
                case (nil, nil):
                    return lhs.name < rhs.name
                case (nil, _?):
                    return true
                case (_?, nil):
                    return false
                }
            }
        return oldestFirst.prefix(matching.count - limit).map { $0.name }
    }

    /// Convenience for tests and callers that only have names. Current filenames
    /// remain fully sortable; legacy names need entries in `legacyModificationDates`.
    static func payloadNamesToPrune(
        _ names: [String],
        prefix: String,
        keepingNewest limit: Int,
        legacyModificationDates: [String: Date] = [:]
    ) -> [String] {
        payloadNamesToPrune(
            names.map { StoredPayload(name: $0, modificationDate: legacyModificationDates[$0]) },
            prefix: prefix,
            keepingNewest: limit
        )
    }

    /// Recovers the absolute time a payload was written. Current names
    /// (full-UUID identifier) are UTC; legacy names (4-character identifier)
    /// use the file's modification date because their local-time name alone is
    /// ambiguous after a timezone change. Unrecognized names sort first and
    /// order lexically among themselves.
    private static func stampedDate(
        in name: String,
        prefix: String,
        legacyModificationDate: Date?
    ) -> Date? {
        let format = "yyyyMMdd-HHmmss-SSS"
        let stem = name.dropFirst(prefix.count).dropLast(".json".count)
        guard stem.dropFirst(format.count).first == "-" else { return nil }
        let identifier = stem.dropFirst(format.count + 1)

        if identifier.count == 4 {
            return legacyModificationDate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.date(from: String(stem.prefix(format.count)))
    }

    // MARK: - Summaries

    private func trackSummary(of payload: MXMetricPayload) {
        var properties: [String: Sendable] = [
            "payload_end": payload.timeStampEnd.timeIntervalSince1970
        ]

        if let launch = payload.applicationLaunchMetrics,
           let firstDraw = Self.averageSeconds(of: launch.histogrammedTimeToFirstDraw) {
            properties["avg_time_to_first_draw_s"] = firstDraw
        }
        if let responsiveness = payload.applicationResponsivenessMetrics {
            let hangs = responsiveness.histogrammedApplicationHangTime
            properties["hang_count"] = Self.totalCount(of: hangs)
            if let avgHang = Self.averageSeconds(of: hangs) {
                properties["avg_hang_s"] = avgHang
            }
        }
        if let memory = payload.memoryMetrics {
            properties["peak_memory_mb"] = memory.peakMemoryUsage.converted(to: .megabytes).value
        }
        if let exits = payload.applicationExitMetrics {
            let foreground = exits.foregroundExitData
            properties["fg_abnormal_exits"] = foreground.cumulativeAbnormalExitCount
            properties["fg_watchdog_exits"] = foreground.cumulativeAppWatchdogExitCount
            properties["fg_memory_limit_exits"] = foreground.cumulativeMemoryResourceLimitExitCount
        }

        track(name: "metrickit_metrics_received", properties: properties)
    }

    private func trackSummary(of payload: MXDiagnosticPayload) {
        let properties: [String: Sendable] = [
            "payload_end": payload.timeStampEnd.timeIntervalSince1970,
            "crashes": payload.crashDiagnostics?.count ?? 0,
            "hangs": payload.hangDiagnostics?.count ?? 0,
            "cpu_exceptions": payload.cpuExceptionDiagnostics?.count ?? 0,
            "disk_write_exceptions": payload.diskWriteExceptionDiagnostics?.count ?? 0
        ]

        track(name: "metrickit_diagnostics_received", properties: properties)
    }

    private func track(name: String, properties: [String: Sendable]) {
        Task { @MainActor in
            Analytics.track(name: name, properties: properties)
        }
    }

    private static func averageSeconds(of histogram: MXHistogram<UnitDuration>) -> Double? {
        var weightedSum = 0.0
        var count = 0
        let enumerator = histogram.bucketEnumerator
        while let bucket = enumerator.nextObject() as? MXHistogramBucket<UnitDuration> {
            let start = bucket.bucketStart.converted(to: .seconds).value
            let end = bucket.bucketEnd.converted(to: .seconds).value
            weightedSum += (start + end) / 2 * Double(bucket.bucketCount)
            count += Int(bucket.bucketCount)
        }
        guard count > 0 else { return nil }
        return weightedSum / Double(count)
    }

    private static func totalCount(of histogram: MXHistogram<UnitDuration>) -> Int {
        var count = 0
        let enumerator = histogram.bucketEnumerator
        while let bucket = enumerator.nextObject() as? MXHistogramBucket<UnitDuration> {
            count += Int(bucket.bucketCount)
        }
        return count
    }
}
