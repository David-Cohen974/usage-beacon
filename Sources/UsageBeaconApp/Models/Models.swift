import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case cursorPersonal
    case cursorAdmin
    case anthropicAdmin
    case manual
    case customREST

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursorPersonal:
            return "Cursor Personal"
        case .cursorAdmin:
            return "Cursor Admin"
        case .anthropicAdmin:
            return "Anthropic Admin"
        case .manual:
            return "Manual Budget"
        case .customREST:
            return "Custom REST"
        }
    }

    var description: String {
        switch self {
        case .cursorPersonal:
            return "Signs into Cursor like the web UI and reads your personal usage page. No admin API key required."
        case .cursorAdmin:
            return "Uses Cursor's Team Admin API and expects a Team API key, not a User API key."
        case .anthropicAdmin:
            return "Uses Anthropic's admin cost report API."
        case .manual:
            return "Works without any vendor API."
        case .customREST:
            return "Maps any JSON API into the dashboard."
        }
    }

    var defaultDisplayName: String {
        switch self {
        case .cursorPersonal:
            return "Cursor Personal"
        case .cursorAdmin:
            return "Cursor"
        case .anthropicAdmin:
            return "Claude"
        case .manual:
            return "Manual Budget"
        case .customREST:
            return "REST Provider"
        }
    }
}

struct GlobalSettings: Codable, Equatable {
    var showFloatingHUD: Bool = true
    var refreshIntervalMinutes: Int = 1
    var useCalendarAdjustments: Bool = true
    var selectedCalendarIDs: [String] = []
    var workingDaysPerWeek: Int = 5
    var workingWeekSchedule: WorkingWeekSchedule = .systemDefault
    var customWorkingWeekdays: [Int] = [2, 3, 4, 5, 6]

    private enum CodingKeys: String, CodingKey {
        case showFloatingHUD
        case refreshIntervalMinutes
        case useCalendarAdjustments
        case selectedCalendarIDs
        case workingDaysPerWeek
        case workingWeekSchedule
        case customWorkingWeekdays
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showFloatingHUD = try container.decodeIfPresent(Bool.self, forKey: .showFloatingHUD) ?? true
        refreshIntervalMinutes = max(1, try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 1)
        useCalendarAdjustments = try container.decodeIfPresent(Bool.self, forKey: .useCalendarAdjustments) ?? true
        selectedCalendarIDs = try container.decodeIfPresent([String].self, forKey: .selectedCalendarIDs) ?? []
        workingDaysPerWeek = min(7, max(1, try container.decodeIfPresent(Int.self, forKey: .workingDaysPerWeek) ?? 5))
        workingWeekSchedule = try container.decodeIfPresent(WorkingWeekSchedule.self, forKey: .workingWeekSchedule) ?? .systemDefault
        customWorkingWeekdays = Self.normalizedCustomWorkingWeekdays(
            try container.decodeIfPresent([Int].self, forKey: .customWorkingWeekdays) ?? [2, 3, 4, 5, 6]
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showFloatingHUD, forKey: .showFloatingHUD)
        try container.encode(refreshIntervalMinutes, forKey: .refreshIntervalMinutes)
        try container.encode(useCalendarAdjustments, forKey: .useCalendarAdjustments)
        try container.encode(selectedCalendarIDs, forKey: .selectedCalendarIDs)
        try container.encode(workingDaysPerWeek, forKey: .workingDaysPerWeek)
        try container.encode(workingWeekSchedule, forKey: .workingWeekSchedule)
        try container.encode(Self.normalizedCustomWorkingWeekdays(customWorkingWeekdays), forKey: .customWorkingWeekdays)
    }

    var effectiveWorkingDaysPerWeek: Int {
        switch workingWeekSchedule {
        case .custom:
            Self.normalizedCustomWorkingWeekdays(customWorkingWeekdays).count
        case .mondayStart, .sundayStart, .systemDefault:
            min(7, max(1, workingDaysPerWeek))
        }
    }

    var normalizedCustomWorkingWeekdays: [Int] {
        Self.normalizedCustomWorkingWeekdays(customWorkingWeekdays)
    }

    static func normalizedCustomWorkingWeekdays(_ weekdays: [Int]) -> [Int] {
        let validDays = Array(Set(weekdays.filter { (1 ... 7).contains($0) })).sorted()
        return validDays.isEmpty ? [2, 3, 4, 5, 6] : validDays
    }
}

enum WorkingWeekSchedule: String, Codable, CaseIterable, Identifiable {
    case systemDefault
    case mondayStart
    case sundayStart
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemDefault:
            return "System Default"
        case .mondayStart:
            return "Monday Start"
        case .sundayStart:
            return "Sunday Start"
        case .custom:
            return "Custom Weekdays"
        }
    }

    var shortTitle: String {
        switch self {
        case .systemDefault:
            return "System"
        case .mondayStart:
            return "Mon start"
        case .sundayStart:
            return "Sun start"
        case .custom:
            return "Custom"
        }
    }
}

struct CursorPersonalSettings: Codable, Equatable {
    var usagePageURL: String = "https://cursor.com/dashboard/usage"
    var monthlyBudgetOverrideUSD: Decimal = 0
    var budgetResetDay: Int = 1

    init(
        usagePageURL: String = "https://cursor.com/dashboard/usage",
        monthlyBudgetOverrideUSD: Decimal = 0,
        budgetResetDay: Int = 1
    ) {
        self.usagePageURL = usagePageURL
        self.monthlyBudgetOverrideUSD = monthlyBudgetOverrideUSD
        self.budgetResetDay = max(1, min(budgetResetDay, 28))
    }

    private enum CodingKeys: String, CodingKey {
        case usagePageURL
        case monthlyBudgetOverrideUSD
        case budgetResetDay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usagePageURL = try container.decodeIfPresent(String.self, forKey: .usagePageURL)
            ?? "https://cursor.com/dashboard/usage"
        monthlyBudgetOverrideUSD = try container.decodeIfPresent(
            Decimal.self,
            forKey: .monthlyBudgetOverrideUSD
        ) ?? 0
        budgetResetDay = max(
            1,
            min(try container.decodeIfPresent(Int.self, forKey: .budgetResetDay) ?? 1, 28)
        )
    }
}

struct CursorAdminSettings: Codable, Equatable {
    var apiBaseURL: String = "https://api.cursor.com"
    var accountEmail: String = ""
    var monthlyBudgetOverrideUSD: Decimal = 0
    var useOverallSpend: Bool = true
}

struct AnthropicAdminSettings: Codable, Equatable {
    var apiBaseURL: String = "https://api.anthropic.com"
    var workspaceID: String = ""
    var monthlyBudgetUSD: Decimal = 500
}

struct ManualBudgetSettings: Codable, Equatable {
    var monthlyBudgetUSD: Decimal = 700
    var spentUSD: Decimal = 0
    var spentTodayUSD: Decimal? = nil
    var billingCycleDay: Int = 1
    var lastPromptCostUSD: Decimal = 0
}

struct CustomRESTSettings: Codable, Equatable {
    var endpointURL: String = ""
    var httpMethod: String = "GET"
    var headerName: String = "Authorization"
    var headerValuePrefix: String = "Bearer "
    var monthlyBudgetPath: String = ""
    var spentPath: String = ""
    var spentTodayPath: String = ""
    var remainingPath: String = ""
    var resetDatePath: String = ""
    var lastPromptCostPath: String = ""
    var dateFormat: String = "iso8601"
    var fallbackBillingCycleDay: Int = 1
    var monthlyBudgetOverrideUSD: Decimal = 0
}

struct StoredProvider: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ProviderKind
    var displayName: String
    var isEnabled: Bool
    var cursorPersonal: CursorPersonalSettings?
    var cursor: CursorAdminSettings?
    var anthropic: AnthropicAdminSettings?
    var manual: ManualBudgetSettings?
    var customREST: CustomRESTSettings?

    init(
        id: UUID = UUID(),
        kind: ProviderKind,
        displayName: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName ?? kind.defaultDisplayName
        self.isEnabled = isEnabled
        switch kind {
        case .cursorPersonal:
            cursorPersonal = CursorPersonalSettings()
            cursor = nil
            anthropic = nil
            manual = nil
            customREST = nil
        case .cursorAdmin:
            cursorPersonal = nil
            cursor = CursorAdminSettings()
            anthropic = nil
            manual = nil
            customREST = nil
        case .anthropicAdmin:
            cursorPersonal = nil
            cursor = nil
            anthropic = AnthropicAdminSettings()
            manual = nil
            customREST = nil
        case .manual:
            cursorPersonal = nil
            cursor = nil
            anthropic = nil
            manual = ManualBudgetSettings()
            customREST = nil
        case .customREST:
            cursorPersonal = nil
            cursor = nil
            anthropic = nil
            manual = nil
            customREST = CustomRESTSettings()
        }
    }

    static func example() -> StoredProvider {
        var provider = StoredProvider(kind: .manual, displayName: "Example Cursor Budget")
        provider.manual = ManualBudgetSettings(
            monthlyBudgetUSD: 700,
            spentUSD: 218.40,
            spentTodayUSD: 19.80,
            billingCycleDay: 1,
            lastPromptCostUSD: 2.37
        )
        return provider
    }

    var secretAccount: String {
        "usage-beacon-\(id.uuidString)"
    }
}

struct AppConfiguration: Codable, Equatable {
    var settings: GlobalSettings
    var providers: [StoredProvider]

    static var example: AppConfiguration {
        AppConfiguration(
            settings: GlobalSettings(),
            providers: [StoredProvider.example()]
        )
    }
}

struct RawBudgetSnapshot {
    var providerID: UUID
    var providerName: String
    var providerKind: ProviderKind
    var monthlyBudgetUSD: Decimal?
    var spentUSD: Decimal
    var remainingUSD: Decimal?
    var billingCycleStart: Date?
    var billingCycleEnd: Date
    var spentTodayUSD: Decimal? = nil
    var lastPromptCostUSD: Decimal?
    var notes: [String]
}

struct ProviderSnapshotState: Identifiable, Equatable {
    var id: UUID
    var providerName: String
    var providerKind: ProviderKind
    var isEnabled: Bool
    var isLoading: Bool
    var monthlyBudgetUSD: Decimal?
    var spentUSD: Decimal?
    var remainingUSD: Decimal?
    var billingCycleEnd: Date?
    var workingDaysRemaining: Int?
    var perWorkingDayRemainingUSD: Decimal?
    var spentTodayUSD: Decimal?
    var lastPromptCostUSD: Decimal?
    var lastUpdatedAt: Date?
    var notes: [String]
    var errorMessage: String?

    static func placeholder(from provider: StoredProvider) -> ProviderSnapshotState {
        ProviderSnapshotState(
            id: provider.id,
            providerName: provider.displayName,
            providerKind: provider.kind,
            isEnabled: provider.isEnabled,
            isLoading: false,
            monthlyBudgetUSD: nil,
            spentUSD: nil,
            remainingUSD: nil,
            billingCycleEnd: nil,
            workingDaysRemaining: nil,
            perWorkingDayRemainingUSD: nil,
            spentTodayUSD: nil,
            lastPromptCostUSD: nil,
            lastUpdatedAt: nil,
            notes: [],
            errorMessage: nil
        )
    }
}

struct CalendarSource: Identifiable, Equatable {
    var id: String
    var title: String
    var colorHex: String
}

enum ProviderFailure: LocalizedError {
    case misconfigured(String)
    case network(String)
    case parsing(String)

    var errorDescription: String? {
        switch self {
        case let .misconfigured(message):
            return message
        case let .network(message):
            return message
        case let .parsing(message):
            return message
        }
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    static func fromCents(_ value: Decimal) -> Decimal {
        value / 100
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

extension Date {
    init(milliseconds: Double) {
        self = Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
