import Foundation

enum AnthropicAdminProvider {
    static func fetch(
        provider: StoredProvider,
        secretStore: SecretStoring,
        httpClient: HTTPClientProtocol,
        now: Date
    ) async throws -> RawBudgetSnapshot {
        guard let settings = provider.anthropic else {
            throw ProviderFailure.misconfigured("Anthropic settings are missing.")
        }
        guard let apiKey = secretStore.loadSecret(account: provider.secretAccount)?.nilIfBlank else {
            throw ProviderFailure.misconfigured("Anthropic Admin API key is missing.")
        }

        let cycle = BudgetMath.calendarMonthCycle(now: now)
        let spentUSD = try await fetchMonthSpend(
            settings: settings,
            apiKey: apiKey,
            httpClient: httpClient,
            cycle: cycle
        )
        let spentTodayUSD = try await fetchSpend(
            settings: settings,
            apiKey: apiKey,
            httpClient: httpClient,
            interval: DateInterval(
                start: Calendar.current.startOfDay(for: now),
                end: now
            )
        )
        let remaining = max(settings.monthlyBudgetUSD - spentUSD, 0)
        let note = settings.workspaceID.nilIfBlank == nil
            ? "Tracking organization-wide API spend."
            : "Tracking API spend for workspace \(settings.workspaceID)."

        return RawBudgetSnapshot(
            providerID: provider.id,
            providerName: provider.displayName,
            providerKind: provider.kind,
            monthlyBudgetUSD: settings.monthlyBudgetUSD,
            spentUSD: spentUSD,
            remainingUSD: remaining,
            billingCycleStart: cycle.start,
            billingCycleEnd: cycle.end,
            spentTodayUSD: spentTodayUSD,
            lastPromptCostUSD: nil,
            notes: [note, "Anthropic's cost report is daily, so per-prompt cost is not shown."]
        )
    }

    private static func fetchMonthSpend(
        settings: AnthropicAdminSettings,
        apiKey: String,
        httpClient: HTTPClientProtocol,
        cycle: DateInterval
    ) async throws -> Decimal {
        try await fetchSpend(
            settings: settings,
            apiKey: apiKey,
            httpClient: httpClient,
            interval: cycle
        )
    }

    private static func fetchSpend(
        settings: AnthropicAdminSettings,
        apiKey: String,
        httpClient: HTTPClientProtocol,
        interval: DateInterval
    ) async throws -> Decimal {
        let isoFormatter = ISO8601DateFormatter()
        var totalCents: Decimal = 0
        var nextPage: String?

        repeat {
            guard var components = URLComponents(string: settings.apiBaseURL) else {
                throw ProviderFailure.misconfigured("Anthropic API base URL is invalid.")
            }
            components.path = "/v1/organizations/cost_report"
            var queryItems = [
                URLQueryItem(name: "starting_at", value: isoFormatter.string(from: interval.start)),
                URLQueryItem(name: "ending_at", value: isoFormatter.string(from: interval.end)),
                URLQueryItem(name: "group_by[]", value: "workspace_id"),
                URLQueryItem(name: "group_by[]", value: "description"),
                URLQueryItem(name: "limit", value: "31")
            ]
            if let workspaceID = settings.workspaceID.nilIfBlank {
                queryItems.append(URLQueryItem(name: "workspace_ids[]", value: workspaceID))
            }
            if let nextPage {
                queryItems.append(URLQueryItem(name: "page", value: nextPage))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw ProviderFailure.misconfigured("Anthropic cost report URL could not be built.")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("UsageBeacon/1.0", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await httpClient.data(for: request)
            let response = try JSONDecoder().decode(AnthropicCostReportResponse.self, from: data)
            for bucket in response.data {
                for result in bucket.results {
                    if let amount = Decimal(string: result.amount) {
                        totalCents += amount
                    }
                }
            }
            nextPage = response.hasMore ? response.nextPage : nil
        } while nextPage != nil

        return Decimal.fromCents(totalCents)
    }
}

private struct AnthropicCostReportResponse: Decodable {
    var data: [AnthropicCostBucket]
    var hasMore: Bool
    var nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

private struct AnthropicCostBucket: Decodable {
    var startingAt: String?
    var endingAt: String?
    var results: [AnthropicCostResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

private struct AnthropicCostResult: Decodable {
    var amount: String
    var currency: String
    var description: String?
    var workspaceID: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case description
        case workspaceID = "workspace_id"
    }
}
