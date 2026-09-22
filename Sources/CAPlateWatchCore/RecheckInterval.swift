import Foundation

public enum RecheckInterval: Int, CaseIterable, Sendable {
    case oneHour = 1, threeHours = 3, sixHours = 6, twelveHours = 12, oneDay = 24, twoDays = 48

    public static let defaultValue = Self.twelveHours
    public static let preferenceKey = "recheckIntervalHours"
    public var seconds: TimeInterval { TimeInterval(rawValue) * 60 * 60 }
    public var label: String { "\(rawValue) \(rawValue == 1 ? "hour" : "hours")" }

    public static func load(from defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.integer(forKey: preferenceKey)) ?? defaultValue
    }
}

/// Re-evaluate before each request so additions and interval changes during an
/// in-flight request take effect without starting a second checking loop.
public enum CheckSchedule {
    public static func nextPlate(in plates: [Plate], at date: Date, interval: TimeInterval,
                                 attempted: Set<UUID>, force: Bool = false) -> Plate? {
        plates.first { !attempted.contains($0.id) && (force || $0.isDue(at: date, interval: interval)) }
    }
}
