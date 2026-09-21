import Foundation

/// Old names intentionally appear only here to import existing local installs.
public enum LegacyMigration {
    public static func importWatchlist(in applicationSupport: URL) throws -> URL {
        let destination = applicationSupport.appendingPathComponent("CA Plate Watch/watchlist.json")
        let legacy = applicationSupport.appendingPathComponent("PlateWatch/watchlist.json")
        let files = FileManager.default
        if !files.fileExists(atPath: destination.path), files.fileExists(atPath: legacy.path) {
            let data = try Data(contentsOf: legacy)
            _ = try JSONDecoder().decode([Plate].self, from: data)
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        return destination
    }
}
