import Foundation

final class ConfigurationStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support", directoryHint: .isDirectory)
        self.fileURL = appSupport
            .appending(path: "UsageBeacon", directoryHint: .isDirectory)
            .appending(path: "configuration.json")
    }

    func load() -> AppConfiguration {
        guard
            fileManager.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL)
        else {
            return .example
        }

        do {
            return try JSONDecoder().decode(AppConfiguration.self, from: data)
        } catch {
            return .example
        }
    }

    func save(_ configuration: AppConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }
}
