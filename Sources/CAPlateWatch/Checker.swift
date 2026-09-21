import Foundation
import CAPlateWatchCore

enum Checker {
    static func check(_ plate: String) async throws -> Availability {
        try await DMVClient().check(plate)
    }
}
