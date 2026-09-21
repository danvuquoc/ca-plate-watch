import Foundation

public enum Availability: String, Codable, Sendable {
    case unknown, available, unavailable
}

public struct Plate: Codable, Identifiable, Sendable {
    public static let interval: TimeInterval = 6 * 60 * 60
    public let id: UUID
    public let text: String
    public var availability: Availability = .unknown
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var error: String?
    public var unread = false

    public init(text: String) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (2...7).contains(normalized.count),
              normalized.range(of: "^[A-Z0-9 /]+$", options: .regularExpression) != nil,
              normalized.range(of: "[A-Z0-9]", options: .regularExpression) != nil else {
            throw CheckError.message("Use 2–7 letters, numbers, or spaces. Use / for a half-space.")
        }
        self.id = UUID()
        self.text = normalized
    }

    public func isDue(at date: Date) -> Bool {
        lastAttempt.map { date.timeIntervalSince($0) >= Self.interval } ?? true
    }

    @discardableResult
    public mutating func record(_ result: Result<Availability, Error>, at date: Date) -> Bool {
        lastAttempt = date
        switch result {
        case .success(let status):
            let alert = status == .available && availability != .available
            availability = status
            lastSuccess = date
            error = nil
            if alert { unread = true }
            if status == .unavailable { unread = false }
            return alert
        case .failure(let failure):
            error = failure.localizedDescription
            return false
        }
    }
}

public enum CheckError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
