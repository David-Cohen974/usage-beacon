import Foundation

enum CursorAdminProvider {
    static func fetch(
        provider: StoredProvider,
        secretStore: SecretStoring,
        httpClient: HTTPClientProtocol,
        now: Date
    ) async throws -> RawBudgetSnapshot {
        guard let settings = provider.cursor else {
            throw ProviderFailure.misconfigured("Cursor settings are missing.")
        }
        guard let accountEmail = settings.accountEmail.nilIfBlank else {
            throw ProviderFailure.misconfigured("Cursor account email is required.")
        }
        guard let apiKey = secretStore.loadSecret(account: provider.secretAccount)?.nilIfBlank else {
            throw ProviderFailure.misconfigured("Cursor API key is missing.")
        }

        let spendRequest = try makeRequest(
            apiBaseURL: settings.apiBaseURL,
            path: "teams/spend",
            apiKey: apiKey,
            body: CursorSpendRequest(searchTerm: accountEmail, page: 1, pageSize: 1000)
        )
        let (spendData, _) = try await httpClient.data(for: spendRequest)
        let spendResponse = try JSONDecoder().decode(CursorSpendResponse.self, from: spendData)

        guard let member = spendResponse.teamMemberSpend.first(where: {
            $0.email.caseInsensitiveCompare(accountEmail) == .orderedSame
        }) else {
            throw ProviderFailure.parsing("Cursor returned no spend row for \(accountEmail).")
        }

        let cycleStart = Date(milliseconds: spendResponse.subscriptionCycleStart)
        let cycleEnd = Calendar.current.date(byAdding: .month, value: 1, to: cycleStart) ?? cycleStart
        let budgetOverride = settings.monthlyBudgetOverrideUSD > 0 ? settings.monthlyBudgetOverrideUSD : nil
        let derivedBudget = budgetOverride
            ?? member.monthlyLimitDollars
            ?? (member.effectivePerUserLimitDollars > 0 ? member.effectivePerUserLimitDollars : nil)
        let spent = Decimal.fromCents(settings.useOverallSpend ? member.overallSpendCents : member.spendCents)
        let remaining = derivedBudget.map { max($0 - spent, 0) }
        let dailyUsage = try await fetchDailyUsageSummary(
            provider: provider,
            settings: settings,
            apiKey: apiKey,
            httpClient: httpClient,
            now: now
        )

        return RawBudgetSnapshot(
            providerID: provider.id,
            providerName: provider.displayName,
            providerKind: provider.kind,
            monthlyBudgetUSD: derivedBudget,
            spentUSD: spent,
            remainingUSD: remaining,
            billingCycleStart: cycleStart,
            billingCycleEnd: cycleEnd,
            spentTodayUSD: dailyUsage.spentTodayUSD,
            lastPromptCostUSD: dailyUsage.lastPromptCostUSD,
            notes: [
                settings.useOverallSpend
                    ? "Using overall spend, including included usage."
                    : "Using on-demand spend only."
            ]
        )
    }

    private static func fetchDailyUsageSummary(
        provider: StoredProvider,
        settings: CursorAdminSettings,
        apiKey: String,
        httpClient: HTTPClientProtocol,
        now: Date
    ) async throws -> CursorDailyUsageSummary {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let request = try makeRequest(
            apiBaseURL: settings.apiBaseURL,
            path: "teams/filtered-usage-events",
            apiKey: apiKey,
            body: CursorUsageEventsRequest(
                startDate: startOfDay.timeIntervalSince1970 * 1000,
                endDate: now.timeIntervalSince1970 * 1000,
                page: 1,
                pageSize: 1000,
                email: settings.accountEmail
            )
        )
        let (data, _) = try await httpClient.data(for: request)
        let response = try JSONDecoder().decode(CursorUsageEventsResponse.self, from: data)
        let latestPromptCostUSD = response.usageEvents
            .max(by: { $0.timestampDate < $1.timestampDate })?
            .chargedCents
            .map(Decimal.fromCents)
        let chargedEvents = response.usageEvents.compactMap(\.chargedCents)
        let spentTodayUSD = chargedEvents.isEmpty ? nil : Decimal.fromCents(chargedEvents.reduce(0, +))

        return CursorDailyUsageSummary(
            spentTodayUSD: spentTodayUSD,
            lastPromptCostUSD: latestPromptCostUSD
        )
    }

    private static func makeRequest<Body: Encodable>(
        apiBaseURL: String,
        path: String,
        apiKey: String,
        body: Body
    ) throws -> URLRequest {
        guard let baseURL = URL(string: apiBaseURL) else {
            throw ProviderFailure.misconfigured("Cursor API base URL is invalid.")
        }

        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func basicAuthHeader(apiKey: String) -> String {
        let token = Data("\(apiKey):".utf8).base64EncodedString()
        return "Basic \(token)"
    }
}

private struct CursorSpendRequest: Encodable {
    var searchTerm: String
    var page: Int
    var pageSize: Int
}

private struct CursorUsageEventsRequest: Encodable {
    var startDate: Double
    var endDate: Double
    var page: Int
    var pageSize: Int
    var email: String
}

private struct CursorSpendResponse: Decodable {
    var teamMemberSpend: [CursorSpendMember]
    var subscriptionCycleStart: Double
}

private struct CursorSpendMember: Decodable {
    var userId: String
    var spendCents: Decimal
    var overallSpendCents: Decimal
    var name: String
    var email: String
    var role: String
    var hardLimitOverrideDollars: Decimal?
    var monthlyLimitDollars: Decimal?
    var effectivePerUserLimitDollars: Decimal
}

private struct CursorUsageEventsResponse: Decodable {
    var usageEvents: [CursorUsageEvent]
}

private struct CursorUsageEvent: Decodable {
    var timestamp: String
    var chargedCents: Decimal?

    var timestampDate: Date {
        if let milliseconds = Double(timestamp) {
            return Date(milliseconds: milliseconds)
        }
        return .distantPast
    }
}

private struct CursorDailyUsageSummary {
    var spentTodayUSD: Decimal?
    var lastPromptCostUSD: Decimal?
}
