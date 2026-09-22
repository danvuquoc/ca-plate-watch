import Foundation

public enum Availability: String, Codable, Sendable {
    case unknown, available, unavailable
}

public struct Plate: Codable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    // Raw identifiers intentionally survive decoding when a newer catalog is unknown.
    public let vehicleTypeID: String
    public let designID: String
    public let veteranDecalID: String?
    public var availability: Availability = .unknown
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var error: String?
    public var unread = false

    public init(text: String, vehicleType: VehicleType = .automobile,
                designID: String = PlateCatalog.defaultDesignID, veteranDecalID: String? = nil) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.id = UUID()
        self.text = normalized
        self.vehicleTypeID = vehicleType.rawValue
        self.designID = designID
        self.veteranDecalID = veteranDecalID
        try validateSelection()
    }

    public var vehicleType: VehicleType? { VehicleType(rawValue: vehicleTypeID) }
    public var design: PlateDesign? { PlateCatalog.design(id: designID) }
    public var selectionLabel: String {
        "\(vehicleType?.label ?? "Unsupported vehicle (\(vehicleTypeID))") · \(design?.name ?? "Unsupported design (\(designID))")"
    }
    public var notificationTitle: String { "\(text) is available" }
    public var notificationBody: String {
        "\(selectionLabel). The DMV checker reports availability. Open CA Plate Watch to visit the DMV and order."
    }
    public var selectionError: String? {
        do { try validateSelection(); return nil }
        catch { return error.localizedDescription }
    }

    public func validateSelection() throws {
        guard let vehicleType, let design else {
            throw CheckError.message("Unsupported saved vehicle or design. Update the app or remove and re-add this entry.")
        }
        guard design.supports(vehicleType) else {
            throw CheckError.message("\(design.name) is not offered by the online checker for \(vehicleType.label).")
        }
        if design.requiresDecal {
            guard let veteranDecalID, VeteranDecal.decal(id: veteranDecalID) != nil else {
                throw CheckError.message("Select a supported Veterans’ Organization decal.")
            }
        } else if veteranDecalID != nil {
            throw CheckError.message("This design does not use a Veterans’ Organization decal.")
        }
        try design.validate(text)
    }

    public func matchesSelection(of other: Plate) -> Bool {
        text == other.text && vehicleTypeID == other.vehicleTypeID && designID == other.designID
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, vehicleTypeID, designID, veteranDecalID, availability, lastAttempt, lastSuccess, error, unread
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        vehicleTypeID = try values.decodeIfPresent(String.self, forKey: .vehicleTypeID) ?? VehicleType.automobile.rawValue
        designID = try values.decodeIfPresent(String.self, forKey: .designID) ?? PlateCatalog.defaultDesignID
        veteranDecalID = try values.decodeIfPresent(String.self, forKey: .veteranDecalID)
        availability = try values.decode(Availability.self, forKey: .availability)
        lastAttempt = try values.decodeIfPresent(Date.self, forKey: .lastAttempt)
        lastSuccess = try values.decodeIfPresent(Date.self, forKey: .lastSuccess)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        unread = try values.decode(Bool.self, forKey: .unread)
    }

    public func isDue(at date: Date, interval: TimeInterval) -> Bool {
        lastAttempt.map { date.timeIntervalSince($0) >= interval } ?? true
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
