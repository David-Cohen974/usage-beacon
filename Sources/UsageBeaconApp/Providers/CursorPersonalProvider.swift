import Foundation

enum CursorPersonalProvider {
    static func fetch(
        provider: StoredProvider,
        now: Date
    ) async throws -> RawBudgetSnapshot {
        guard let settings = provider.cursorPersonal else {
            throw ProviderFailure.misconfigured("Cursor personal settings are missing.")
        }

        let parsed = try await fetchUsageSummary(
            pageURL: settings.usagePageURL,
            budgetOverrideUSD: settings.monthlyBudgetOverrideUSD > 0 ? settings.monthlyBudgetOverrideUSD : nil,
            budgetResetDay: settings.budgetResetDay,
            now: now
        )

        return RawBudgetSnapshot(
            providerID: provider.id,
            providerName: provider.displayName,
            providerKind: provider.kind,
            monthlyBudgetUSD: parsed.monthlyBudgetUSD,
            spentUSD: parsed.spentUSD,
            remainingUSD: parsed.remainingUSD,
            billingCycleStart: nil,
            billingCycleEnd: parsed.billingCycleEnd,
            spentTodayUSD: parsed.spentTodayUSD,
            lastPromptCostUSD: parsed.lastPromptCostUSD,
            notes: parsed.notes
        )
    }

    private static func fetchUsageSummary(
        pageURL: String,
        budgetOverrideUSD: Decimal?,
        budgetResetDay: Int,
        now: Date
    ) async throws -> CursorPersonalParsedUsage {
        let sessionController = await MainActor.run {
            CursorDashboardSessionController.shared
        }
        let isCursorHostedPage = URL(string: pageURL)?.host.map { host in
            let lowercasedHost = host.lowercased()
            return lowercasedHost.contains("cursor.com") || lowercasedHost.contains("cursor.sh")
        } ?? false

        if !isCursorHostedPage {
            let pageSnapshot = try await sessionController.loadUsagePage(pageURL: pageURL)
            return try CursorPersonalUsageParser.parse(
                page: pageSnapshot,
                now: now,
                budgetOverrideUSD: budgetOverrideUSD,
                budgetResetDay: budgetResetDay
            )
        }

        do {
            let (data, _) = try await sessionController.authenticatedGET(
                urlString: "https://cursor.com/api/usage-summary"
            )
            let summary = try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: data)
            let eventMetrics = await fetchUsageEventMetricsIfAvailable(
                sessionController: sessionController,
                billingCycleStart: summary.billingCycleStart,
                requiresTeamScope: summary.limitType?.lowercased() == "team",
                now: now
            )
            return try mapUsageSummary(
                summary,
                budgetOverrideUSD: budgetOverrideUSD,
                budgetResetDay: budgetResetDay,
                now: now,
                todaySpentUSD: eventMetrics.spentTodayUSD,
                lastPromptCostUSD: eventMetrics.lastPromptCostUSD
            )
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("401") {
                throw ProviderFailure.misconfigured("Cursor personal is not signed in yet. Click Connect, sign in, and refresh.")
            }
        }

        let pageSnapshot = try await sessionController.loadUsagePage(pageURL: pageURL)
        var parsed = try CursorPersonalUsageParser.parse(
            page: pageSnapshot,
            now: now,
            budgetOverrideUSD: budgetOverrideUSD,
            budgetResetDay: budgetResetDay
        )
        let eventMetrics = await fetchUsageEventMetricsIfAvailable(
            sessionController: sessionController,
            billingCycleStart: nil,
            requiresTeamScope: false,
            now: now
        )
        parsed.spentTodayUSD = eventMetrics.spentTodayUSD
        parsed.lastPromptCostUSD = eventMetrics.lastPromptCostUSD
        if eventMetrics.spentTodayUSD != nil || eventMetrics.lastPromptCostUSD != nil {
            parsed.notes.removeAll { $0.hasPrefix("Last prompt cost") }
            parsed.notes.append("Today's spend and last prompt cost are calculated from Cursor's signed-in usage events.")
        }
        return parsed
    }

    static func mapUsageSummary(
        _ summary: CursorUsageSummaryResponse,
        budgetOverrideUSD: Decimal?,
        budgetResetDay: Int = 1,
        now: Date,
        todaySpentUSD: Decimal? = nil,
        lastPromptCostUSD: Decimal? = nil
    ) throws -> CursorPersonalParsedUsage {
        let overall = summary.individualUsage?.overall
        let onDemand = summary.teamUsage?.onDemand

        let chosenUsage: CursorUsageBucket?
        let usageLabel: String
        if let overall, overall.enabled {
            chosenUsage = overall
            usageLabel = "included total usage"
        } else if let onDemand, onDemand.enabled {
            chosenUsage = onDemand
            usageLabel = "on-demand usage"
        } else {
            chosenUsage = nil
            usageLabel = "usage"
        }

        guard let chosenUsage else {
            throw ProviderFailure.parsing("Cursor usage summary did not expose a usable budget bucket.")
        }

        let monthlyBudget = budgetOverrideUSD
            ?? chosenUsage.limit.map(Decimal.fromCents)
        let spent = Decimal.fromCents(chosenUsage.used)
        let remaining = budgetOverrideUSD.map { max($0 - spent, 0) }
            ?? chosenUsage.remaining.map(Decimal.fromCents)
            ?? monthlyBudget.map { max($0 - spent, 0) }
        let billingCycleEnd = budgetOverrideUSD == nil
            ? (summary.billingCycleEnd ?? BudgetMath.calendarMonthCycle(now: now).end)
            : BudgetMath.billingCycle(resetDay: budgetResetDay, now: now).end

        var notes = [
            "Using Cursor's signed-in personal session, not the admin API.",
            "Reading Cursor's private usage summary endpoint for \(usageLabel)."
        ]
        if let onDemand, onDemand.enabled {
            notes.append("On-demand usage so far: \(Decimal.fromCents(onDemand.used).formatted(.currency(code: "USD"))).")
        }
        if budgetOverrideUSD != nil {
            notes.append("Using your monthly budget override.")
        }
        if budgetOverrideUSD != nil {
            notes.append("Daily runway follows your budget reset day (\(budgetResetDay)), not Cursor's subscription renewal date.")
        }
        if todaySpentUSD != nil || lastPromptCostUSD != nil {
            notes.append("Today's spend and last prompt cost are calculated from Cursor's signed-in usage events.")
        }
        if lastPromptCostUSD == nil {
            notes.append("Cursor did not return a recent prompt event for this billing cycle.")
        }

        return CursorPersonalParsedUsage(
            monthlyBudgetUSD: monthlyBudget,
            spentUSD: spent,
            remainingUSD: remaining,
            billingCycleEnd: billingCycleEnd,
            spentTodayUSD: todaySpentUSD,
            lastPromptCostUSD: lastPromptCostUSD,
            notes: notes
        )
    }

    private static func fetchUsageEventMetricsIfAvailable(
        sessionController: CursorDashboardSessionController,
        billingCycleStart: Date?,
        requiresTeamScope: Bool,
        now: Date
    ) async -> CursorPersonalEventMetrics {
        let scope = await fetchUsageEventScope(sessionController: sessionController)
        if requiresTeamScope, scope.teamID == nil || scope.userID == nil {
            return CursorPersonalEventMetrics()
        }

        let spentTodayUSD = await fetchTodaySpendIfAvailable(
            sessionController: sessionController,
            scope: scope,
            now: now
        )
        let lastPromptCostUSD = await fetchLastPromptCostIfAvailable(
            sessionController: sessionController,
            scope: scope,
            billingCycleStart: billingCycleStart ?? BudgetMath.calendarMonthCycle(now: now).start,
            now: now
        )
        return CursorPersonalEventMetrics(
            spentTodayUSD: spentTodayUSD,
            lastPromptCostUSD: lastPromptCostUSD
        )
    }

    private static func fetchUsageEventScope(
        sessionController: CursorDashboardSessionController
    ) async -> CursorUsageEventScope {
        let userID: Int?
        if let (data, _) = try? await sessionController.authenticatedGET(
            urlString: "https://cursor.com/api/auth/me"
        ) {
            userID = authenticatedUserID(from: data)
        } else {
            userID = nil
        }

        let emptyObject = Data("{}".utf8)
        let teamID: Int?
        if let (data, _) = try? await sessionController.authenticatedPOST(
            urlString: "https://cursor.com/api/dashboard/get-user-organizations",
            jsonData: emptyObject
        ) {
            teamID = defaultTeamID(from: data)
        } else {
            teamID = nil
        }

        return CursorUsageEventScope(userID: userID, teamID: teamID)
    }

    static func authenticatedUserID(from data: Data) -> Int? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let dictionary = json as? [String: Any]
        else {
            return nil
        }
        return integer(from: dictionary["id"])
    }

    static func defaultTeamID(from data: Data) -> Int? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let dictionary = json as? [String: Any],
            let organizations = dictionary["organizations"] as? [[String: Any]]
        else {
            return nil
        }

        for organization in organizations {
            if let defaultTeamID = integer(from: organization["defaultTeamId"]) {
                return defaultTeamID
            }
            if let teams = organization["teams"] as? [[String: Any]],
               let firstTeamID = teams.lazy.compactMap({ integer(from: $0["teamId"]) }).first {
                return firstTeamID
            }
        }
        return nil
    }

    private static func fetchTodaySpendIfAvailable(
        sessionController: CursorDashboardSessionController,
        scope: CursorUsageEventScope,
        now: Date
    ) async -> Decimal? {
        let endpoint = "https://cursor.com/api/dashboard/get-filtered-usage-events"
        let pageSize = 500
        let maximumPages = 3
        var calendar = Calendar.current
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let startMilliseconds = Int64(start.timeIntervalSince1970 * 1_000)
        let endMilliseconds = Int64(end.timeIntervalSince1970 * 1_000) - 1
        var totalUSD: Decimal = 0
        var receivedEvents = 0

        for page in 1 ... maximumPages {
            guard let jsonData = usageEventRequestData(
                startMilliseconds: startMilliseconds,
                endMilliseconds: endMilliseconds,
                page: page,
                pageSize: pageSize,
                scope: scope
            ) else {
                return nil
            }

            let result: (Data, HTTPURLResponse)
            do {
                result = try await sessionController.authenticatedPOST(
                    urlString: endpoint,
                    jsonData: jsonData
                )
            } catch {
                return nil
            }

            let (data, _) = result
            guard let pageInfo = usageEventPageInfo(data) else {
                return nil
            }

            if pageInfo.eventCount == 0 {
                return receivedEvents == 0 ? 0 : totalUSD
            }

            guard let pageSpend = parseTodaySpendResponse(data, now: now) else {
                return nil
            }

            totalUSD += pageSpend
            receivedEvents += pageInfo.eventCount
            if let totalEventCount = pageInfo.totalEventCount,
               receivedEvents >= totalEventCount {
                return totalUSD
            }
        }

        // Never publish a partial daily value when the safety page cap is reached.
        return nil
    }

    private static func fetchLastPromptCostIfAvailable(
        sessionController: CursorDashboardSessionController,
        scope: CursorUsageEventScope,
        billingCycleStart: Date,
        now: Date
    ) async -> Decimal? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        guard let jsonData = usageEventRequestData(
            startMilliseconds: Int64(billingCycleStart.timeIntervalSince1970 * 1_000),
            endMilliseconds: Int64(end.timeIntervalSince1970 * 1_000) - 1,
            page: 1,
            pageSize: 1,
            scope: scope
        ) else {
            return nil
        }

        guard let (data, _) = try? await sessionController.authenticatedPOST(
            urlString: "https://cursor.com/api/dashboard/get-filtered-usage-events",
            jsonData: jsonData
        ) else {
            return nil
        }
        return parseLastPromptCostResponse(data)
    }

    private static func usageEventRequestData(
        startMilliseconds: Int64,
        endMilliseconds: Int64,
        page: Int,
        pageSize: Int,
        scope: CursorUsageEventScope
    ) -> Data? {
        var requestBody: [String: Any] = [
            "startDate": String(startMilliseconds),
            "endDate": String(endMilliseconds),
            "page": page,
            "pageSize": pageSize
        ]
        if let teamID = scope.teamID, let userID = scope.userID {
            requestBody["teamId"] = teamID
            requestBody["userId"] = userID
        }
        return try? JSONSerialization.data(withJSONObject: requestBody)
    }

    static func usageEventPageInfo(
        _ data: Data
    ) -> (eventCount: Int, totalEventCount: Int?)? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let dictionary = json as? [String: Any]
        else {
            return nil
        }

        let events = dictionary["usageEventsDisplay"] as? [Any]
            ?? dictionary["usageEvents"] as? [Any]
        if dictionary.isEmpty {
            // Cursor's protobuf JSON omits zero-valued fields and serializes an empty page as `{}`.
            return (0, 0)
        }
        guard let events else {
            return nil
        }

        let totalEventCount = (dictionary["totalUsageEventsCount"] as? NSNumber)?.intValue
            ?? Int(dictionary["totalUsageEventsCount"] as? String ?? "")
        return (events.count, totalEventCount)
    }

    static func parseTodaySpendResponse(_ data: Data, now: Date) -> Decimal? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return directTodaySpend(in: json)
            ?? nestedTodaySpend(in: json, now: now)
    }

    static func parseLastPromptCostResponse(_ data: Data) -> Decimal? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let dictionary = json as? [String: Any],
            let events = dictionary["usageEventsDisplay"] as? [Any]
                ?? dictionary["usageEvents"] as? [Any]
        else {
            return nil
        }

        return events.compactMap { event -> (date: Date, cost: Decimal)? in
            guard
                let dictionary = event as? [String: Any],
                let date = dateValue(in: dictionary),
                let cost = spendValue(in: dictionary)
            else {
                return nil
            }
            return (date, cost)
        }
        .max { $0.date < $1.date }?
        .cost
    }

    private static func directTodaySpend(in json: Any) -> Decimal? {
        guard let dictionary = json as? [String: Any] else {
            return nil
        }

        let centsKeys = [
            "todaySpendCents",
            "today_spend_cents",
            "todayCostCents",
            "today_cost_cents"
        ]
        for key in centsKeys {
            if let value = decimal(from: dictionary[key]) {
                return Decimal.fromCents(value)
            }
        }

        let usdKeys = [
            "todaySpendUSD",
            "today_spend_usd",
            "todayCostUSD",
            "today_cost_usd",
            "todaySpend",
            "today_spend"
        ]
        for key in usdKeys {
            if let value = decimal(from: dictionary[key]) {
                return value
            }
        }

        return nil
    }

    private static func nestedTodaySpend(in json: Any, now: Date) -> Decimal? {
        if let array = json as? [Any] {
            return sumTodayEntries(array, now: now)
        }

        guard let dictionary = json as? [String: Any] else {
            return nil
        }

        let preferredKeys = [
            "data",
            "results",
            "items",
            "days",
            "dailySpend",
            "daily_spend",
            "spendByCategory",
            "spend_by_category",
            "categories"
        ]
        for key in preferredKeys {
            if let value = dictionary[key], let parsed = nestedTodaySpend(in: value, now: now) {
                return parsed
            }
        }

        for value in dictionary.values {
            if let parsed = nestedTodaySpend(in: value, now: now) {
                return parsed
            }
        }

        return nil
    }

    private static func sumTodayEntries(_ entries: [Any], now: Date) -> Decimal? {
        var total: Decimal = 0
        var foundMatch = false

        for entry in entries {
            guard
                let dictionary = entry as? [String: Any],
                let entryDate = dateValue(in: dictionary),
                Calendar.current.isDate(entryDate, inSameDayAs: now),
                let amount = spendValue(in: dictionary)
            else {
                continue
            }

            total += amount
            foundMatch = true
        }

        return foundMatch ? total : nil
    }

    private static func dateValue(in dictionary: [String: Any]) -> Date? {
        let keys = [
            "date",
            "day",
            "timestamp",
            "starting_at",
            "startDate",
            "bucket_start"
        ]

        for key in keys {
            if let value = dictionary[key], let parsed = parseDate(value) {
                return parsed
            }
        }

        return nil
    }

    private static func spendValue(in dictionary: [String: Any]) -> Decimal? {
        let centsKeys = [
            "spendCents",
            "spend_cents",
            "costCents",
            "cost_cents",
            "amountCents",
            "amount_cents",
            "totalCents",
            "total_cents",
            "chargedCents",
            "charged_cents"
        ]
        for key in centsKeys {
            if let value = decimal(from: dictionary[key]) {
                return Decimal.fromCents(value)
            }
        }

        let usdKeys = [
            "spendUSD",
            "spend_usd",
            "costUSD",
            "cost_usd",
            "amountUSD",
            "amount_usd",
            "totalUSD",
            "total_usd",
            "spend",
            "cost",
            "amount",
            "total"
        ]
        for key in usdKeys {
            if let value = decimal(from: dictionary[key]) {
                return value
            }
        }

        if let nestedCategories = dictionary["categories"] as? [Any] {
            let nestedValues = nestedCategories.compactMap { category -> Decimal? in
                guard let categoryDictionary = category as? [String: Any] else {
                    return nil
                }
                return spendValue(in: categoryDictionary)
            }
            if nestedValues.isEmpty == false {
                return nestedValues.reduce(0, +)
            }
        }

        if let tokenUsage = dictionary["tokenUsage"] as? [String: Any],
           let tokenCents = decimal(from: tokenUsage["totalCents"]) {
            let cursorFee = decimal(from: dictionary["cursorTokenFee"]) ?? 0
            return Decimal.fromCents(tokenCents + cursorFee)
        }

        if let formattedCost = dictionary["usageBasedCosts"] as? String {
            let normalized = formattedCost
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Decimal(string: normalized) {
                return value
            }
        }

        return nil
    }

    private static func decimal(from value: Any?) -> Decimal? {
        switch value {
        case let decimal as Decimal:
            return decimal
        case let number as NSNumber:
            return number.decimalValue
        case let text as String:
            return Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func integer(from value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func parseDate(_ value: Any) -> Date? {
        if let date = value as? Date {
            return date
        }

        if let number = value as? NSNumber {
            return date(from: number.stringValue)
        }

        if let text = value as? String {
            return date(from: text)
        }

        return nil
    }

    private static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let milliseconds = Double(trimmed) {
            if trimmed.count >= 13 {
                return Date(milliseconds: milliseconds)
            }
            return Date(timeIntervalSince1970: milliseconds)
        }

        if let isoDate = ISO8601DateFormatter().date(from: trimmed) {
            return isoDate
        }

        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "MMM d, yyyy", "MMMM d, yyyy"] {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }
}

private struct CursorUsageEventScope {
    var userID: Int?
    var teamID: Int?
}

private struct CursorPersonalEventMetrics {
    var spentTodayUSD: Decimal?
    var lastPromptCostUSD: Decimal?

    init(
        spentTodayUSD: Decimal? = nil,
        lastPromptCostUSD: Decimal? = nil
    ) {
        self.spentTodayUSD = spentTodayUSD
        self.lastPromptCostUSD = lastPromptCostUSD
    }
}

struct CursorPersonalParsedUsage: Equatable {
    var monthlyBudgetUSD: Decimal?
    var spentUSD: Decimal
    var remainingUSD: Decimal?
    var billingCycleEnd: Date
    var spentTodayUSD: Decimal? = nil
    var lastPromptCostUSD: Decimal?
    var notes: [String]
}

enum CursorPersonalUsageParser {
    static func parse(
        page: CursorDashboardPageSnapshot,
        now: Date,
        budgetOverrideUSD: Decimal?,
        budgetResetDay: Int = 1
    ) throws -> CursorPersonalParsedUsage {
        let normalizedText = page.bodyText.replacingOccurrences(of: "\u{00a0}", with: " ")
        let spentAndBudget = parseSpentAndBudget(from: normalizedText)
        let spent = spentAndBudget?.spent ?? parseSpentOnly(from: normalizedText) ?? 0
        let monthlyBudget = budgetOverrideUSD
            ?? spentAndBudget?.budget
            ?? parseBudgetOnly(from: normalizedText)
        let remaining = monthlyBudget.map { max($0 - spent, 0) }
        let cycleEnd: Date
        if budgetOverrideUSD == nil {
            cycleEnd = try parseBillingCycleEnd(from: normalizedText, now: now)
        } else {
            cycleEnd = BudgetMath.billingCycle(resetDay: budgetResetDay, now: now).end
        }

        if spentAndBudget == nil, monthlyBudget == nil, spent == 0 {
            throw ProviderFailure.parsing("UsageBeacon could not read dollar usage from Cursor's page. Open the Usage page in Connect and try again, or set a budget override.")
        }

        var notes: [String] = ["Using Cursor's personal dashboard session, not the admin API."]
        if spentAndBudget?.matchedPattern == .onDemandUsage {
            notes.append("Parsed the on-demand usage card from Cursor's dashboard.")
        } else if spentAndBudget?.matchedPattern == .limit {
            notes.append("Parsed the current-usage limit card from Cursor's dashboard.")
        }
        if budgetOverrideUSD != nil {
            notes.append("Using your monthly budget override.")
        }
        if budgetOverrideUSD != nil {
            notes.append("Daily runway follows your budget reset day (\(budgetResetDay)), not Cursor's subscription renewal date.")
        }
        notes.append("Last prompt cost is not present in Cursor's dashboard page text.")

        return CursorPersonalParsedUsage(
            monthlyBudgetUSD: monthlyBudget,
            spentUSD: spent,
            remainingUSD: remaining,
            billingCycleEnd: cycleEnd,
            spentTodayUSD: nil,
            lastPromptCostUSD: nil,
            notes: notes
        )
    }

    private static func parseBillingCycleEnd(from text: String, now: Date) throws -> Date {
        if let resetText = firstMatch(
            in: text,
            pattern: #"(?im)resets?\s+([^\n]+)"#
        )?.first,
           let parsedDate = parseResetDate(resetText) {
            return parsedDate
        }

        if let daysText = firstMatch(
            in: text,
            pattern: #"(?im)renews?\s+in\s+(\d+)\s+days?"#
        )?.first,
           let days = Int(daysText) {
            let startOfToday = Calendar.current.startOfDay(for: now)
            return Calendar.current.date(byAdding: .day, value: days + 1, to: startOfToday) ?? startOfToday
        }

        let fallback = Calendar.current.date(byAdding: .month, value: 1, to: now)
        return fallback ?? now
    }

    private static func parseSpentAndBudget(from text: String) -> (spent: Decimal, budget: Decimal, matchedPattern: MatchedPattern)? {
        if let match = firstMatch(
            in: text,
            pattern: #"\$([0-9][0-9,]*(?:\.\d+)?)\s*/\s*\$([0-9][0-9,]*(?:\.\d+)?)\s*on-demand usage"#
        ),
           let spent = decimal(match[0]),
           let budget = decimal(match[1]) {
            return (spent, budget, .onDemandUsage)
        }

        if let match = firstMatch(
            in: text,
            pattern: #"\$([0-9][0-9,]*(?:\.\d+)?)\s*of\s*\$([0-9][0-9,]*(?:\.\d+)?)\s*limit"#
        ),
           let spent = decimal(match[0]),
           let budget = decimal(match[1]) {
            return (spent, budget, .limit)
        }

        return nil
    }

    private static func parseSpentOnly(from text: String) -> Decimal? {
        if let match = firstMatch(
            in: text,
            pattern: #"(?is)current usage\s*\$([0-9][0-9,]*(?:\.\d+)?)"#
        )?.first {
            return decimal(match)
        }

        return nil
    }

    private static func parseBudgetOnly(from text: String) -> Decimal? {
        if let match = firstMatch(
            in: text,
            pattern: #"(?im)(?:monthly spending limit|hard limit)\s*:?\s*\$([0-9][0-9,]*(?:\.\d+)?)"#
        )?.first {
            return decimal(match)
        }

        return nil
    }

    private static func parseResetDate(_ rawValue: String) -> Date? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "/", with: "-")

        if let date = ISO8601DateFormatter().date(from: trimmed) {
            return date
        }

        for format in [
            "yyyy-MM-dd",
            "yyyy-M-d",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "d MMM yyyy",
            "d MMMM yyyy"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }

        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        return (1 ..< match.numberOfRanges).compactMap { index in
            let matchRange = match.range(at: index)
            guard let range = Range(matchRange, in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private static func decimal(_ value: String) -> Decimal? {
        Decimal(string: value.replacingOccurrences(of: ",", with: ""))
    }

    private enum MatchedPattern {
        case onDemandUsage
        case limit
    }
}

struct CursorUsageSummaryResponse: Decodable {
    var billingCycleStart: Date?
    var billingCycleEnd: Date?
    var membershipType: String?
    var limitType: String?
    var isUnlimited: Bool?
    var individualUsage: CursorUsageSummaryBuckets?
    var teamUsage: CursorTeamUsageSummaryBuckets?

    private enum CodingKeys: String, CodingKey {
        case billingCycleStart
        case billingCycleEnd
        case membershipType
        case limitType
        case isUnlimited
        case individualUsage
        case teamUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let iso8601 = ISO8601DateFormatter()
        if let billingCycleStartString = try container.decodeIfPresent(String.self, forKey: .billingCycleStart) {
            billingCycleStart = iso8601.date(from: billingCycleStartString)
        } else {
            billingCycleStart = nil
        }
        if let billingCycleEndString = try container.decodeIfPresent(String.self, forKey: .billingCycleEnd) {
            billingCycleEnd = iso8601.date(from: billingCycleEndString)
        } else {
            billingCycleEnd = nil
        }
        membershipType = try container.decodeIfPresent(String.self, forKey: .membershipType)
        limitType = try container.decodeIfPresent(String.self, forKey: .limitType)
        isUnlimited = try container.decodeIfPresent(Bool.self, forKey: .isUnlimited)
        individualUsage = try container.decodeIfPresent(CursorUsageSummaryBuckets.self, forKey: .individualUsage)
        teamUsage = try container.decodeIfPresent(CursorTeamUsageSummaryBuckets.self, forKey: .teamUsage)
    }
}

struct CursorUsageSummaryBuckets: Decodable {
    var overall: CursorUsageBucket?
}

struct CursorTeamUsageSummaryBuckets: Decodable {
    var onDemand: CursorUsageBucket?
}

struct CursorUsageBucket: Decodable {
    var enabled: Bool
    var used: Decimal
    var limit: Decimal?
    var remaining: Decimal?
}
