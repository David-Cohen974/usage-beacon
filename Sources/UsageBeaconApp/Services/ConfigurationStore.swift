import Foundation

struct ConfigurationRecovery: Equatable {
    let backupURL: URL
    let message: String
}

enum ConfigurationStoreError: LocalizedError {
    case recoveryRequired(URL)

    var errorDescription: String? {
        switch self {
        case let .recoveryRequired(url):
            return "The unreadable configuration is still at \(url.path). Move or repair it before saving new settings."
        }
    }
}

final class ConfigurationStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private(set) var lastRecovery: ConfigurationRecovery?
    private var saveBlockedByRecovery = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support", directoryHint: .isDirectory)
        self.fileURL = appSupport
            .appending(path: "UsageBeacon", directoryHint: .isDirectory)
            .appending(path: "configuration.json")
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() -> AppConfiguration {
        lastRecovery = nil
        saveBlockedByRecovery = false
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
            return Self.isLegacyExampleConfiguration(configuration) ? .empty : configuration
        } catch {
            preserveUnreadableConfiguration(causedBy: error)
            return .empty
        }
    }

    private static func isLegacyExampleConfiguration(_ configuration: AppConfiguration) -> Bool {
        guard configuration.providers.count == 1,
              let provider = configuration.providers.first,
              provider.kind == .manual,
              provider.displayName == "Example Cursor Budget",
              provider.isEnabled,
              provider.codex == nil,
              provider.cursorPersonal == nil,
              provider.cursor == nil,
              provider.claudePersonal == nil,
              provider.anthropic == nil,
              provider.customREST == nil,
              let manual = provider.manual else {
            return false
        }

        return approximatelyEqual(manual.monthlyBudgetUSD, to: 700)
            && approximatelyEqual(manual.spentUSD, to: 218.40)
            && approximatelyEqual(manual.spentTodayUSD, to: 19.80)
            && manual.billingCycleDay == 1
            && approximatelyEqual(manual.lastPromptCostUSD, to: 2.37)
    }

    private static func approximatelyEqual(_ value: Decimal?, to expected: Double) -> Bool {
        guard let value else { return false }
        return abs(NSDecimalNumber(decimal: value).doubleValue - expected) < 0.0001
    }

    func save(_ configuration: AppConfiguration) throws {
        guard saveBlockedByRecovery == false else {
            throw ConfigurationStoreError.recoveryRequired(fileURL)
        }
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

    private func preserveUnreadableConfiguration(causedBy error: Error) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appending(path: "configuration.json.bad-\(timestamp)-\(UUID().uuidString.prefix(8))")

        do {
            try fileManager.moveItem(at: fileURL, to: backupURL)
            saveBlockedByRecovery = false
            lastRecovery = ConfigurationRecovery(
                backupURL: backupURL,
                message: "UsageBeacon could not read your configuration. The original file was preserved as \(backupURL.lastPathComponent). No demo data was loaded."
            )
        } catch let preservationError {
            saveBlockedByRecovery = true
            lastRecovery = ConfigurationRecovery(
                backupURL: fileURL,
                message: "UsageBeacon could not read your configuration and could not move it to a backup. The original file is still at \(fileURL.path). Save operations may fail until it is repaired. \(preservationError.localizedDescription)"
            )
        }
    }
}
