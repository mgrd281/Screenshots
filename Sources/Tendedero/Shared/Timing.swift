import Foundation
import os

/// How long each step of covering a picture takes: marked for Instruments
/// as it runs, and written to the log once the copy is made. Step names and
/// numbers only, never a word of what was read.
enum Timing {
    private static let signposter = OSSignposter(subsystem: "de.ghazarian.Snapfly", category: "Protection")

    /// One step and how long it took, in milliseconds.
    struct Step: Equatable {
        let name: String
        let milliseconds: Int
    }

    /// The last picture covered: how long it took in all, and step by step.
    struct Run: Equatable {
        let milliseconds: Int
        let steps: [Step]
    }

    private static let lock = NSLock()
    private static var kept: Run?

    /// How long the last copy took, for Settings to show.
    static var last: Run? {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }

    /// Runs a step, marked in Instruments and timed. Steps are noted on the
    /// thread that runs them, so two pictures covered at once keep apart.
    @discardableResult
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        let started = Date()
        defer {
            signposter.endInterval(name, state)
            note(Step(name: "\(name)", milliseconds: milliseconds(since: started)))
        }
        return try work()
    }

    /// Starts timing a picture on this thread, with no step left from before.
    static func start() -> Date {
        _ = taken()
        return Date()
    }

    /// Writes the steps noted on this thread since `started` to the log, and
    /// keeps them as the last run.
    static func report(since started: Date) {
        let steps = taken()
        let run = Run(milliseconds: milliseconds(since: started), steps: steps)
        lock.lock()
        kept = run
        lock.unlock()
        let parts = steps.map { "\($0.name) \($0.milliseconds)" }.joined(separator: ", ")
        log.info("Covered in \(run.milliseconds, privacy: .public) ms: \(parts, privacy: .public)")
    }

    // MARK: Over many pictures

    /// What is measured over the pictures protected lately: until the
    /// picture shows, and until its copy is ready to leave.
    enum Measure: String, CaseIterable {
        case shown, ready
    }

    /// How many pictures each measure keeps; numbers only.
    static let remembered = 50

    static func record(_ measure: Measure, _ milliseconds: Int, in defaults: UserDefaults = .standard) {
        let key = "SnapflyTimes." + measure.rawValue
        let times = (defaults.array(forKey: key) as? [Int] ?? []) + [milliseconds]
        defaults.set(Array(times.suffix(remembered)), forKey: key)
    }

    static func recent(_ measure: Measure, in defaults: UserDefaults = .standard) -> [Int] {
        defaults.array(forKey: "SnapflyTimes." + measure.rawValue) as? [Int] ?? []
    }

    /// The value under which this share of them lie, by nearest rank: 0.5
    /// gives the middle one (P50), 0.95 the one only the slowest pass (P95).
    static func percentile(_ values: [Int], _ share: Double) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((share * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    static func milliseconds(since started: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(started) * 1000))
    }

    private static let key = "SnapflyTimingSteps"

    private static func note(_ step: Step) {
        let thread = Thread.current.threadDictionary
        var steps = thread[key] as? [Step] ?? []
        // A long page of small print is read in many steps; a few dozen tell enough.
        guard steps.count < 40 else { return }
        steps.append(step)
        thread[key] = steps
    }

    private static func taken() -> [Step] {
        let thread = Thread.current.threadDictionary
        defer { thread.removeObject(forKey: key) }
        return thread[key] as? [Step] ?? []
    }
}
