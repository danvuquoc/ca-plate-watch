import Foundation

public enum VehicleType: String, CaseIterable, Sendable {
    case automobile = "AUTO", commercial = "COMM", trailer = "TRAI", motorcycle = "MOTO"

    public var label: String {
        switch self {
        case .automobile: return "Automobile"
        case .commercial: return "Commercial"
        case .trailer: return "Trailer"
        case .motorcycle: return "Motorcycle"
        }
    }
}

public enum KidsSymbol: String, CaseIterable, Sendable {
    case heart, star, hand, plus

    public var character: Character {
        switch self {
        case .heart: return "♥"
        case .star: return "★"
        case .hand: return "✋"
        case .plus: return "+"
        }
    }
    public var label: String { "\(character) \(rawValue.capitalized)" }
    public static func matching(_ character: Character) -> Self? {
        allCases.first { $0.character == character }
    }
}

public struct PlateDesign: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// DMV's plateLength, not the number of serialized plateChar fields.
    public let length: Int
    public var requiresSymbol: Bool { id == "K" }
    public var requiresDecal: Bool { id == "V" }

    public func supports(_ vehicle: VehicleType) -> Bool {
        id == "R" || vehicle == .automobile || vehicle == .commercial
    }

    public var inputGuidance: String {
        let lengthHint = requiresSymbol ? "2–6 letters/numbers plus one Kids symbol." : "2–\(length) letters/numbers."
        let extra = length == 7 && !requiresSymbol ? " A half-space allows an eighth position." : ""
        return lengthHint + " Spaces are allowed; / is a half-space. No adjacent half-spaces." + extra
    }

    public func validate(_ text: String) throws {
        let characters = Array(text)
        let symbols = characters.compactMap(KidsSymbol.matching)
        let alphaNumeric = characters.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.count
        let maxPositions = length == 7 && !requiresSymbol && text.contains("/") ? 8 : length
        guard alphaNumeric >= 2,
              characters.count <= maxPositions,
              characters.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == " " || $0 == "/" || (requiresSymbol && KidsSymbol.matching($0) != nil) }),
              !text.contains("//"),
              requiresSymbol ? symbols.count == 1 : symbols.isEmpty else {
            throw CheckError.message(inputGuidance)
        }
    }
}

/// Snapshot of ipp2 version 84's startPers.do form, inspected 2026-09-21.
/// See docs/DMV_CATALOG.md for provenance, eligibility, and wire-format details.
public enum PlateCatalog {
    public static let version = "2026-09-21.1"
    public static let defaultDesignID = "R"
    public static let designs: [PlateDesign] = [
        .init(id: "R", name: "Environmental", length: 7),
        .init(id: "Q", name: "Breast Cancer Awareness", length: 6),
        .init(id: "J", name: "California Museums", length: 6),
        .init(id: "Z", name: "California 1960s Legacy", length: 7),
        .init(id: "I", name: "Pet Lover's", length: 6),
        .init(id: "D", name: "California Agriculture", length: 6),
        .init(id: "G", name: "California Memorial", length: 6),
        .init(id: "W", name: "California Coastal Commission", length: 7),
        .init(id: "H", name: "Lake Tahoe Conservancy", length: 7),
        .init(id: "Y", name: "Yosemite Foundation", length: 7),
        .init(id: "A", name: "California Arts Council", length: 6),
        .init(id: "V", name: "Veterans' Organization", length: 6),
        .init(id: "K", name: "Kids", length: 7)
    ]

    public static func design(id: String) -> PlateDesign? { designs.first { $0.id == id } }
    public static func designs(for vehicle: VehicleType) -> [PlateDesign] { designs.filter { $0.supports(vehicle) } }
}
