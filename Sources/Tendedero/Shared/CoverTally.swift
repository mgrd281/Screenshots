import Foundation

/// How much Snapfly covered in what was sent, day by day, for the one quiet
/// line at the top of Settings › Privacy: "In the last 7 days, Snapfly
/// covered 143 details in 38 photos you sent." Only counts are kept, never
/// what was covered, and only for two weeks.
enum CoverTally {
    static let key = "coverTally"

    /// One day's counts.
    struct Day: Codable, Equatable {
        var photos = 0
        var details = 0
    }

    /// A photo sent with this many details covered. Nothing is counted for
    /// a photo with nothing covered.
    static func note(details: Int, on date: Date = Date(), in defaults: UserDefaults = .standard) {
        guard details > 0 else { return }
        var days = load(from: defaults)
        let day = stamp(date)
        days[day, default: Day()].photos += 1
        days[day, default: Day()].details += details
        // Older than two weeks is no longer needed.
        let oldest = stamp(date.addingTimeInterval(-14 * 24 * 60 * 60))
        days = days.filter { $0.key >= oldest }
        defaults.set(try? JSONEncoder().encode(days), forKey: key)
    }

    /// The seven days up to and with today.
    static func week(until date: Date = Date(), in defaults: UserDefaults = .standard) -> Day {
        let first = stamp(date.addingTimeInterval(-6 * 24 * 60 * 60))
        let last = stamp(date)
        return load(from: defaults).filter { $0.key >= first && $0.key <= last }.values
            .reduce(into: Day()) { sum, day in
                sum.photos += day.photos
                sum.details += day.details
            }
    }

    /// The line Settings shows; nil while nothing was covered this week.
    static func sentence(_ week: Day) -> String? {
        guard week.details > 0 else { return nil }
        if week.details == 1 { return L("In the last 7 days, Snapfly covered one detail in a photo you sent.") }
        return week.photos == 1
            ? String(format: L("In the last 7 days, Snapfly covered %d details in one photo you sent."), week.details)
            : String(format: L("In the last 7 days, Snapfly covered %1$d details in %2$d photos you sent."),
                     week.details, week.photos)
    }

    private static func load(from defaults: UserDefaults) -> [String: Day] {
        guard let data = defaults.data(forKey: key),
              let days = try? JSONDecoder().decode([String: Day].self, from: data) else { return [:] }
        return days
    }

    /// "2026-10-17", in the Mac's own calendar, which sorts as it reads.
    private static func stamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
