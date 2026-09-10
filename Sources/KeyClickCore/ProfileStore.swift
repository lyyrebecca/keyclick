import Foundation

public final class ProfileStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = ProfileStore.defaultFileURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("KeyClick", isDirectory: true).appendingPathComponent("config.json")
    }

    public func load() -> (settings: AppSettings, recoveredFromCorruption: Bool) {
        guard fileManager.fileExists(atPath: fileURL.path) else { return (.empty, false) }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
            return (decoded, false)
        } catch {
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("config-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.moveItem(at: fileURL, to: backup)
            return (.empty, true)
        }
    }

    public func save(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
