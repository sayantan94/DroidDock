import Foundation

/// Uses the phone's modification date; does not infer a photo's capture date.
public struct FileMonth: Hashable, Comparable, Identifiable, Sendable {
    public let year: Int
    public let month: Int
    public var id: String { "\(year)-\(month)" }
    public init(date: Date?, calendar: Calendar = .current) {
        if let date {
            let parts = calendar.dateComponents([.year, .month], from: date)
            year = parts.year ?? 0; month = parts.month ?? 0
        } else { year = 0; month = 0 }
    }
    public var title: String {
        guard month > 0, let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) else { return "Unknown date" }
        let formatter = DateFormatter(); formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
}
