import Foundation

// @unchecked Sendable: formatters are configured in their property initializers and never
// mutated afterwards; Foundation formatters are safe for concurrent reads.
public final class TimeFormatter: @unchecked Sendable {
    public static let shared = TimeFormatter()

    private let colonFormatterMinutes: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]

        return formatter
    }()

    private let colonFormatterHours: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]

        return formatter
    }()

    private let shortFormatMinutes: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .abbreviated, allowedUnits: [.minute])
    }()

    private let shortFormatHours: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .abbreviated, allowedUnits: [.hour])
    }()

    private let shortTimeFormatter: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .abbreviated, allowedUnits: [.minute, .hour])
    }()

    private let subMinuteFormatter: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .abbreviated, allowedUnits: [.second])
    }()

    private let appleFormatterSeconds: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .full, allowedUnits: [.second])
    }()

    private let appleFormatterMinutes: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .full, allowedUnits: [.minute])
    }()

    private let appleFormatterHours: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .full, allowedUnits: [.hour])
    }()

    private let appleFormatterDays: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .full, allowedUnits: [.day])
    }()

    private let appleFormatterYears: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .full, allowedUnits: [.year])
    }()

    private let minutesHoursFormatter: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .full, allowedUnits: [.hour, .minute])
    }()

    private let minutesHoursFormatterMedium: DateComponentsFormatter = {
        TimeFormatter.localizedFormatter(style: .short, allowedUnits: [.hour, .minute])
    }()

    public func playTimeFormat(time: TimeInterval, showSeconds: Bool = true) -> String {
        if time.isNaN || !time.isFinite { return "0:00" }

        if time < 1.hours {
            let formatter = showSeconds ? colonFormatterMinutes : shortFormatMinutes
            return formatter.string(from: time) ?? "0:00"
        }

        if showSeconds {
            return colonFormatterHours.string(from: time) ?? "0:00"
        } else {
            return Duration.seconds(time).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
    }

    public func singleUnitFormattedShortestTime(time: TimeInterval) -> String {
        if time.isNaN || !time.isFinite { return "" }

        if time < 1.minutes {
            return subMinuteFormatter.string(from: time) ?? ""
        } else if time < 1.hours {
            return shortFormatMinutes.string(from: time) ?? ""
        } else {
            return shortFormatHours.string(from: time) ?? ""
        }
    }

    public func multipleUnitFormattedShortTime(time: TimeInterval) -> String {
        if time.isNaN || !time.isFinite { return "" }

        if time < 60.seconds {
            return subMinuteFormatter.string(from: time) ?? ""
        }

        return shortTimeFormatter.string(from: time) ?? ""
    }

    public func multipleUnitFormattedSpokenTime(time: TimeInterval) -> String {
        if time.isNaN || !time.isFinite { return "" }

        if time < 60.seconds {
            return appleFormatterSeconds.string(from: time) ?? ""
        }

        return minutesHoursFormatter.string(from: time) ?? ""
    }

    public func minutesHoursFormatted(time: TimeInterval) -> String {
        if time.isNaN || !time.isFinite { return "" }

        return minutesHoursFormatter.string(from: time) ?? ""
    }

    public func minutesFormatted(time: TimeInterval) -> String {
        if time.isNaN || !time.isFinite { return "" }

        return appleFormatterMinutes.string(from: time) ?? ""
    }

    private let relativeFormatter = RelativeDateTimeFormatter()

    public func appleStyleElapsedString(date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    public func appleStyleTillString(date: Date) -> String? {
        let time = date.timeIntervalSinceNow
        var timeStr: String?
        if time <= 1.minute {
            timeStr = appleFormatterSeconds.string(from: time)
        } else if time <= 1.hour {
            timeStr = appleFormatterMinutes.string(from: time)
        } else if time <= 1.days {
            timeStr = appleFormatterHours.string(from: time)
        } else if time <= 365.days {
            timeStr = appleFormatterDays.string(from: time)
        } else {
            timeStr = appleFormatterYears.string(from: time)
        }

        return timeStr
    }

    public class func currentUTCTimeInMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func createUsFormatter(allowedUnits: NSCalendar.Unit) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = allowedUnits
        formatter.zeroFormattingBehavior = [.dropAll]

        return formatter
    }

    private static func localizedFormatter(style: DateComponentsFormatter.UnitsStyle, allowedUnits: NSCalendar.Unit) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = style
        formatter.allowedUnits = allowedUnits
        formatter.zeroFormattingBehavior = [.dropAll]

        return formatter
    }
}
