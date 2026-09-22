import Foundation

public enum UsageBeaconWidgetData {
    public static let appGroupIdentifier = "Y3XM9Q3AZT.com.rekindle.usagebeacon"
    public static let widgetKind = "UsageBeaconBudgetWidget"

    fileprivate static let snapshotKey = "usageBeacon.widgetSnapshot"
}

public struct UsageBeaconWidgetProvider: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let sourceName: String
    public let primaryValue: String
    public let secondaryValue: String
    public let remainingUSD: Double?
    public let spentTodayUSD: Double?
    public let perWorkingDayUSD: Double?
    public let utilization: Double?
    public let hasError: Bool

    public init(
        id: UUID,
        name: String,
        sourceName: String,
        primaryValue: String,
        secondaryValue: String,
        remainingUSD: Double?,
        spentTodayUSD: Double?,
        perWorkingDayUSD: Double?,
        utilization: Double?,
        hasError: Bool
    ) {
        self.id = id
        self.name = name
        self.sourceName = sourceName
        self.primaryValue = primaryValue
        self.secondaryValue = secondaryValue
        self.remainingUSD = remainingUSD
        self.spentTodayUSD = spentTodayUSD
        self.perWorkingDayUSD = perWorkingDayUSD
        self.utilization = utilization
        self.hasError = hasError
    }
}

public struct UsageBeaconWidgetSnapshot: Codable, Equatable, Sendable {
    public let updatedAt: Date
    public let providers: [UsageBeaconWidgetProvider]

    /// A partial or stale total looks like a valid budget. Hide the aggregate
    /// while any source reports a failure, leaving the source rows visible.
    public var totalRemainingUSD: Double? {
        guard !providers.contains(where: \.hasError) else { return nil }
        let values = providers.compactMap(\.remainingUSD)
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
        let total = values.reduce(0, +)
        return total.isFinite ? total : nil
    }

    public init(updatedAt: Date = Date(), providers: [UsageBeaconWidgetProvider]) {
        self.updatedAt = updatedAt
        self.providers = providers
    }
}

public enum UsageBeaconWidgetSnapshotStore {
    public static func snapshotURL() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: UsageBeaconWidgetData.appGroupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return container.appendingPathComponent("widget-snapshot.json")
    }

    public static func save(_ snapshot: UsageBeaconWidgetSnapshot) throws {
        try save(snapshot, to: snapshotURL())
    }

    public static func save(_ snapshot: UsageBeaconWidgetSnapshot, to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Commit the complete payload before asking the other process to reload.
        try data.write(to: url, options: .atomic)
    }

    public static func load() -> UsageBeaconWidgetSnapshot? {
        guard let url = try? snapshotURL() else { return nil }
        if FileManager.default.fileExists(atPath: url.path) {
            return load(from: url)
        }
        // Read the old store only until the upgraded app publishes its first file.
        guard let data = UserDefaults(suiteName: UsageBeaconWidgetData.appGroupIdentifier)?
            .data(forKey: UsageBeaconWidgetData.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(UsageBeaconWidgetSnapshot.self, from: data)
    }

    public static func load(from url: URL) -> UsageBeaconWidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UsageBeaconWidgetSnapshot.self, from: data)
    }
}
