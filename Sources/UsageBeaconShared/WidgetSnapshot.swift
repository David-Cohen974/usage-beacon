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

    public init(updatedAt: Date = Date(), providers: [UsageBeaconWidgetProvider]) {
        self.updatedAt = updatedAt
        self.providers = providers
    }
}

public enum UsageBeaconWidgetSnapshotStore {
    public static func save(_ snapshot: UsageBeaconWidgetSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        sharedDefaults.set(data, forKey: UsageBeaconWidgetData.snapshotKey)
    }

    public static func load() -> UsageBeaconWidgetSnapshot? {
        guard let data = sharedDefaults.data(forKey: UsageBeaconWidgetData.snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(UsageBeaconWidgetSnapshot.self, from: data)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: UsageBeaconWidgetData.appGroupIdentifier) ?? .standard
    }
}
