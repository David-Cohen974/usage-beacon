import Foundation

enum ClaudePersonalProvider {
    static func fetch(
        provider: StoredProvider,
        now: Date
    ) async throws -> RawBudgetSnapshot {
        guard let settings = provider.claudePersonal else {
            throw ProviderFailure.misconfigured("Claude personal settings are missing.")
        }

        let sessionController = await MainActor.run {
            ClaudeDashboardSessionController.shared
        }
        let page = try await sessionController.loadUsagePage(pageURL: settings.usagePageURL)
        let budgetOverride = settings.monthlyBudgetOverrideUSD > 0
            ? settings.monthlyBudgetOverrideUSD
            : nil
        let parsed: ClaudePersonalParsedUsage

        if let usageEndpoint = usageEndpoint(from: page) {
            let (data, _) = try await sessionController.authenticatedGET(urlString: usageEndpoint)
            let summary = try JSONDecoder().decode(ClaudePersonalUsageSummaryResponse.self, from: data)
            parsed = try mapUsageSummary(
                summary,
                budgetOverrideUSD: budgetOverride,
                budgetResetDay: settings.budgetResetDay,
                now: now
            )
        } else {
            parsed = try ClaudePersonalUsageParser.parse(
                page: page,
                now: now,
                budgetOverrideUSD: budgetOverride,
                budgetResetDay: settings.budgetResetDay
            )
        }

        return RawBudgetSnapshot(
            providerID: provider.id,
            providerName: provider.displayName,
            providerKind: provider.kind,
            monthlyBudgetUSD: parsed.monthlyBudgetUSD,
            spentUSD: parsed.spentUSD,
            remainingUSD: parsed.remainingUSD,
            billingCycleStart: nil,
            billingCycleEnd: parsed.billingCycleEnd,
            spentTodayUSD: nil,
            lastPromptCostUSD: nil,
            notes: parsed.notes,
            usageWindows: parsed.usageWindows
        )
    }

    static func usageEndpoint(from page: ClaudeDashboardPageSnapshot) -> String? {
        if let exactEndpoint = page.resourceURLs.first(where: { url in
            guard let components = URLComponents(string: url) else {
                return false
            }
            return components.host?.lowercased() == "claude.ai"
                && components.path.range(
                    of: #"^/api/organizations/[^/]+/usage$"#,
                    options: .regularExpression
                ) != nil
        }) {
            return exactEndpoint
        }

        for resourceURL in page.resourceURLs {
            guard let components = URLComponents(string: resourceURL) else {
                continue
            }
            let path = components.path
            guard let match = path.range(
                of: #"/api/organizations/([^/]+)/"#,
                options: .regularExpression
            ) else {
                continue
            }
            let matchedPath = String(path[match])
            let organizationID = matchedPath
                .replacingOccurrences(of: "/api/organizations/", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if organizationID.isEmpty == false {
                return "https://claude.ai/api/organizations/\(organizationID)/usage"
            }
        }

        return nil
    }

    static func mapUsageSummary(
        _ summary: ClaudePersonalUsageSummaryResponse,
        budgetOverrideUSD: Decimal?,
        budgetResetDay: Int,
        now: Date
    ) throws -> ClaudePersonalParsedUsage {
        if summary.memberDashboardAvailable == false {
            throw ProviderFailure.misconfigured(
                "Claude member analytics is not available for this account. Ask an organization owner to enable Organization settings → Usage → Member analytics."
            )
        }

        var usageWindows: [UsageWindowSnapshot] = []
        if let fiveHour = summary.fiveHour {
            usageWindows.append(
                UsageWindowSnapshot(
                    kind: .fiveHour,
                    title: "5-hour window",
                    usedPercent: min(max(fiveHour.utilization, 0), 100),
                    resetsAt: fiveHour.resetsAt
                )
            )
        }
        if let sevenDay = summary.sevenDay {
            usageWindows.append(
                UsageWindowSnapshot(
                    kind: .sevenDay,
                    title: "7-day window",
                    usedPercent: min(max(sevenDay.utilization, 0), 100),
                    resetsAt: sevenDay.resetsAt
                )
            )
        }

        let reportedCurrencies = [summary.spend?.used?.currency, summary.spend?.limit?.currency]
            .compactMap { $0?.uppercased() }
        if let unsupportedCurrency = reportedCurrencies.first(where: { $0 != "USD" }) {
            throw ProviderFailure.misconfigured(
                "Claude returned \(unsupportedCurrency) spend, but UsageBeacon's personal budget fields are in USD. The app will not display that amount as dollars."
            )
        }

        let reportedSpend = summary.spend?.enabled == true
            ? summary.spend.flatMap { spend in
                spend.used.map { $0.dollars }
            }
            : nil
        let reportedLimit = summary.spend?.enabled == true
            ? summary.spend.flatMap { spend in
                spend.limit.map { $0.dollars }
            }
            : nil
        let legacySpend = summary.extraUsage.flatMap { extraUsage -> Decimal? in
            guard extraUsage.isEnabled else {
                return nil
            }
            return extraUsage.usedCredits.map {
                $0 / decimalPowerOfTen(extraUsage.decimalPlaces ?? 2)
            }
        }
        let legacyLimit = summary.extraUsage.flatMap { extraUsage -> Decimal? in
            guard extraUsage.isEnabled else {
                return nil
            }
            return extraUsage.monthlyLimit.map {
                $0 / decimalPowerOfTen(extraUsage.decimalPlaces ?? 2)
            }
        }

        let spent = reportedSpend ?? legacySpend ?? 0
        let monthlyBudget = budgetOverrideUSD ?? reportedLimit ?? legacyLimit
        let remaining = monthlyBudget.map { max($0 - spent, 0) }

        guard !usageWindows.isEmpty || monthlyBudget != nil || reportedSpend != nil || legacySpend != nil else {
            throw ProviderFailure.parsing(
                "Claude's usage endpoint did not expose a rolling quota or personal spend limit for this account."
            )
        }

        var notes = [
            "Using Claude's signed-in personal session and private usage endpoint, not an admin API key."
        ]
        if !usageWindows.isEmpty {
            notes.append("Rolling usage percentages come directly from Claude.")
        }
        if reportedLimit != nil || legacyLimit != nil {
            notes.append("Personal spend and limit come from Claude Member analytics.")
        }
        if budgetOverrideUSD != nil {
            notes.append("Using your monthly budget override with reset day \(budgetResetDay).")
        }
        notes.append("Per-prompt cost is not exposed on Claude's personal usage endpoint.")

        let cycleEnd = budgetOverrideUSD != nil
            ? BudgetMath.billingCycle(resetDay: budgetResetDay, now: now).end
            : BudgetMath.calendarMonthCycle(now: now).end

        return ClaudePersonalParsedUsage(
            monthlyBudgetUSD: monthlyBudget,
            spentUSD: spent,
            remainingUSD: remaining,
            billingCycleEnd: cycleEnd,
            usageWindows: usageWindows,
            notes: notes
        )
    }

    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else {
            return 1
        }
        return (0 ..< exponent).reduce(Decimal(1)) { value, _ in value * 10 }
    }
}

struct ClaudePersonalUsageSummaryResponse: Decodable {
    var fiveHour: ClaudePersonalUsageBucket?
    var sevenDay: ClaudePersonalUsageBucket?
    var extraUsage: ClaudePersonalExtraUsage?
    var spend: ClaudePersonalSpend?
    var memberDashboardAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case extraUsage = "extra_usage"
        case spend
        case memberDashboardAvailable = "member_dashboard_available"
    }
}

struct ClaudePersonalUsageBucket: Decodable {
    var utilization: Decimal
    var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try container.decode(Decimal.self, forKey: .utilization)
        if let rawDate = try container.decodeIfPresent(String.self, forKey: .resetsAt) {
            let formatter = ISO8601DateFormatter()
            resetsAt = formatter.date(from: rawDate)
            if resetsAt == nil {
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                resetsAt = formatter.date(from: rawDate)
            }
        } else {
            resetsAt = nil
        }
    }
}

struct ClaudePersonalExtraUsage: Decodable {
    var isEnabled: Bool
    var monthlyLimit: Decimal?
    var usedCredits: Decimal?
    var decimalPlaces: Int?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case decimalPlaces = "decimal_places"
    }
}

struct ClaudePersonalSpend: Decodable {
    var used: ClaudeMoneyAmount?
    var limit: ClaudeMoneyAmount?
    var enabled: Bool
}

struct ClaudeMoneyAmount: Decodable {
    var amountMinor: Decimal
    var currency: String?
    var exponent: Int

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
        case exponent
    }

    var dollars: Decimal {
        let divisor = exponent > 0
            ? (0 ..< exponent).reduce(Decimal(1)) { value, _ in value * 10 }
            : 1
        return amountMinor / divisor
    }
}

struct ClaudePersonalParsedUsage: Equatable {
    var monthlyBudgetUSD: Decimal?
    var spentUSD: Decimal
    var remainingUSD: Decimal?
    var billingCycleEnd: Date
    var usageWindows: [UsageWindowSnapshot]
    var notes: [String]
}

enum ClaudePersonalUsageParser {
    static func parse(
        page: ClaudeDashboardPageSnapshot,
        now: Date,
        budgetOverrideUSD: Decimal?,
        budgetResetDay: Int = 1
    ) throws -> ClaudePersonalParsedUsage {
        let normalizedText = page.bodyText
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")

        if looksLikeDisabledMemberAnalytics(normalizedText) {
            throw ProviderFailure.misconfigured(
                "Claude member analytics is not available for this account. Ask an organization owner to enable Organization settings → Usage → Member analytics."
            )
        }

        let usageWindows = parseUsageWindows(from: normalizedText, now: now)
        let spendPair = parseSpentAndBudget(from: normalizedText)
        let pageSpent = spendPair?.spent ?? parseSpentOnly(from: normalizedText)
        let monthlyBudget = budgetOverrideUSD
            ?? spendPair?.budget
            ?? parseBudgetOnly(from: normalizedText)
        let spent = pageSpent ?? 0
        let remaining = monthlyBudget.map { max($0 - spent, 0) }

        guard !usageWindows.isEmpty || monthlyBudget != nil || pageSpent != nil else {
            throw ProviderFailure.parsing(
                "UsageBeacon could not read Claude usage from Settings → Usage. Leave the Connect window on that page, and make sure Member analytics is enabled for your organization."
            )
        }

        let cycleEnd: Date
        if budgetOverrideUSD != nil {
            cycleEnd = BudgetMath.billingCycle(resetDay: budgetResetDay, now: now).end
        } else if monthlyBudget != nil || pageSpent != nil {
            cycleEnd = BudgetMath.calendarMonthCycle(now: now).end
        } else {
            cycleEnd = usageWindows.first(where: { $0.kind == .sevenDay })?.resetsAt
                ?? usageWindows.first?.resetsAt
                ?? BudgetMath.calendarMonthCycle(now: now).end
        }

        var notes = [
            "Using Claude's signed-in personal session, not an admin API key."
        ]
        if !usageWindows.isEmpty {
            notes.append("Rolling usage percentages come from Claude's own usage view.")
        }
        if monthlyBudget != nil || pageSpent != nil {
            notes.append("Personal spend is limited to what your organization exposes in Member analytics.")
        }
        if budgetOverrideUSD != nil {
            notes.append("Using your monthly budget override with reset day \(budgetResetDay).")
        }
        notes.append("Per-prompt cost is not exposed on Claude's personal usage page.")

        return ClaudePersonalParsedUsage(
            monthlyBudgetUSD: monthlyBudget,
            spentUSD: spent,
            remainingUSD: remaining,
            billingCycleEnd: cycleEnd,
            usageWindows: usageWindows,
            notes: notes
        )
    }

    static func parseUsageWindows(from text: String, now: Date) -> [UsageWindowSnapshot] {
        var windows: [UsageWindowSnapshot] = []

        if let section = boundedSection(
            in: text,
            startPatterns: [
                #"(?i)current\s+session"#,
                #"(?i)(?:five|5)[-\s]?hour(?:\s+window)?"#
            ],
            stopPatterns: [
                #"(?i)current\s+week"#,
                #"(?i)(?:seven|7)[-\s]?day(?:\s+window)?"#,
                #"(?i)extra\s+usage"#
            ]
        ), let usedPercent = parsePercent(from: section) {
            windows.append(
                UsageWindowSnapshot(
                    kind: .fiveHour,
                    title: "5-hour window",
                    usedPercent: min(max(usedPercent, 0), 100),
                    resetsAt: parseResetDate(from: section, now: now)
                )
            )
        }

        if let section = boundedSection(
            in: text,
            startPatterns: [
                #"(?i)current\s+week(?:\s*[-–—:]?\s*all\s+models)?"#,
                #"(?i)(?:seven|7)[-\s]?day(?:\s+window)?"#,
                #"(?i)weekly\s+usage"#
            ],
            stopPatterns: [
                #"(?i)extra\s+usage"#,
                #"(?i)(?:sonnet|opus|haiku)(?:\s+only)?"#,
                #"(?i)month-to-date"#
            ]
        ), let usedPercent = parsePercent(from: section) {
            windows.append(
                UsageWindowSnapshot(
                    kind: .sevenDay,
                    title: "7-day window",
                    usedPercent: min(max(usedPercent, 0), 100),
                    resetsAt: parseResetDate(from: section, now: now)
                )
            )
        }

        return windows
    }

    private static func boundedSection(
        in text: String,
        startPatterns: [String],
        stopPatterns: [String]
    ) -> String? {
        let fullRange = NSRange(text.startIndex..., in: text)
        var startLocation: Int?

        for pattern in startPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            if let match = regex.firstMatch(in: text, range: fullRange) {
                startLocation = min(startLocation ?? match.range.location, match.range.location)
            }
        }

        guard let startLocation else {
            return nil
        }
        let startIndex = String.Index(utf16Offset: startLocation, in: text)

        let maximumEndLocation = min(fullRange.length, startLocation + 700)
        var endLocation = maximumEndLocation
        let searchStart = min(startLocation + 1, fullRange.length)
        let searchRange = NSRange(location: searchStart, length: maximumEndLocation - searchStart)

        for pattern in stopPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            if let match = regex.firstMatch(in: text, range: searchRange) {
                endLocation = min(endLocation, match.range.location)
            }
        }

        let endIndex = String.Index(utf16Offset: endLocation, in: text)
        return String(text[startIndex ..< endIndex])
    }

    private static func parsePercent(from section: String) -> Decimal? {
        for pattern in [
            #"(?i)([0-9]+(?:\.\d+)?)\s*%\s*(?:used|utilized)?"#,
            #"(?i)(?:used|utilization)\s*:?[ \t]*([0-9]+(?:\.\d+)?)\s*%"#
        ] {
            if let rawValue = firstMatch(in: section, pattern: pattern)?.first,
               let value = Decimal(string: rawValue) {
                return value
            }
        }
        return nil
    }

    private static func parseResetDate(from section: String, now: Date) -> Date? {
        if let duration = firstMatch(
            in: section,
            pattern: #"(?i)resets?\s+in\s+([^\n]+)"#
        )?.first {
            var seconds = 0
            seconds += (integerMatch(in: duration, pattern: #"(?i)(\d+)\s*(?:days?|d)\b"#) ?? 0) * 86_400
            seconds += (integerMatch(in: duration, pattern: #"(?i)(\d+)\s*(?:hours?|hrs?|h)\b"#) ?? 0) * 3_600
            seconds += (integerMatch(in: duration, pattern: #"(?i)(\d+)\s*(?:minutes?|mins?|m)\b"#) ?? 0) * 60
            if seconds > 0 {
                return now.addingTimeInterval(TimeInterval(seconds))
            }
        }

        guard let rawDate = firstMatch(
            in: section,
            pattern: #"(?i)resets?\s+(?:on\s+|at\s+)?([^\n]+)"#
        )?.first else {
            return nil
        }

        let cleaned = rawDate
            .replacingOccurrences(of: " at ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)

        for (candidate, format) in [
            (cleaned, "MMM d, yyyy h:mm a"),
            (cleaned, "MMMM d, yyyy h:mm a"),
            (cleaned, "MMM d, yyyy"),
            (cleaned, "MMMM d, yyyy"),
            ("\(cleaned), \(currentYear)", "MMM d h:mm a, yyyy"),
            ("\(cleaned), \(currentYear)", "MMMM d h:mm a, yyyy"),
            ("\(cleaned), \(currentYear)", "MMM d, yyyy"),
            ("\(cleaned), \(currentYear)", "MMMM d, yyyy")
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: candidate) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: cleaned)
    }

    private static func parseSpentAndBudget(from text: String) -> (spent: Decimal, budget: Decimal)? {
        for pattern in [
            #"(?is)(?:month-to-date|mtd|extra\s+usage|usage\s+credits).{0,240}?\$([0-9][0-9,]*(?:\.\d+)?).{0,100}?(?:of|/)\s*\$([0-9][0-9,]*(?:\.\d+)?)"#,
            #"(?is)\$([0-9][0-9,]*(?:\.\d+)?)\s*(?:of|/)\s*\$([0-9][0-9,]*(?:\.\d+)?).{0,160}?(?:monthly|spend\s+limit|extra\s+usage|usage\s+credits)"#
        ] {
            if let match = firstMatch(in: text, pattern: pattern),
               match.count >= 2,
               let spent = decimal(match[0]),
               let budget = decimal(match[1]) {
                return (spent, budget)
            }
        }
        return nil
    }

    private static func parseSpentOnly(from text: String) -> Decimal? {
        for pattern in [
            #"(?is)(?:month-to-date|mtd)\s+(?:spend|spent).{0,80}?\$([0-9][0-9,]*(?:\.\d+)?)"#,
            #"(?is)(?:spent|used).{0,40}?\$([0-9][0-9,]*(?:\.\d+)?).{0,100}?(?:this\s+month|month-to-date|usage\s+credits)"#
        ] {
            if let rawValue = firstMatch(in: text, pattern: pattern)?.first {
                return decimal(rawValue)
            }
        }
        return nil
    }

    private static func parseBudgetOnly(from text: String) -> Decimal? {
        for pattern in [
            #"(?is)(?:monthly\s+spend\s+limit|individual\s+limit|your\s+spend\s+limit).{0,80}?\$([0-9][0-9,]*(?:\.\d+)?)"#,
            #"(?is)\$([0-9][0-9,]*(?:\.\d+)?).{0,60}?(?:monthly\s+spend\s+limit|spend\s+limit)"#
        ] {
            if let rawValue = firstMatch(in: text, pattern: pattern)?.first {
                return decimal(rawValue)
            }
        }
        return nil
    }

    private static func looksLikeDisabledMemberAnalytics(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("member analytics")
            && (
                lowered.contains("not enabled")
                    || lowered.contains("disabled")
                    || lowered.contains("ask your admin")
                    || lowered.contains("ask an owner")
            )
    }

    private static func integerMatch(in text: String, pattern: String) -> Int? {
        firstMatch(in: text, pattern: pattern)?.first.flatMap(Int.init)
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        return (1 ..< match.numberOfRanges).compactMap { index in
            let matchRange = match.range(at: index)
            guard matchRange.location != NSNotFound,
                  let range = Range(matchRange, in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private static func decimal(_ value: String) -> Decimal? {
        Decimal(string: value.replacingOccurrences(of: ",", with: ""))
    }
}
