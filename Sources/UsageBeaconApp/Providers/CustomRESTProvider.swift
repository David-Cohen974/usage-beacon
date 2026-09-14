import Foundation

enum CustomRESTProvider {
    static func fetch(
        provider: StoredProvider,
        secretStore: SecretStoring,
        httpClient: HTTPClientProtocol,
        now: Date
    ) async throws -> RawBudgetSnapshot {
        guard let settings = provider.customREST else {
            throw ProviderFailure.misconfigured("Custom REST settings are missing.")
        }
        guard let endpoint = settings.endpointURL.nilIfBlank else {
            throw ProviderFailure.misconfigured("Custom REST endpoint URL is required.")
        }
        guard let url = URL(string: endpoint) else {
            throw ProviderFailure.misconfigured("Custom REST endpoint URL is invalid.")
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.nilIfBlank != nil else {
            throw ProviderFailure.misconfigured("Custom REST endpoint must be an HTTP or HTTPS URL with a host.")
        }
        guard isPublicHost(url.host!) else {
            throw ProviderFailure.misconfigured("Custom REST endpoint cannot target localhost or a private network address.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = settings.httpMethod.isEmpty ? "GET" : settings.httpMethod
        if
            let headerName = settings.headerName.nilIfBlank,
            let secret = secretStore.loadSecret(account: provider.secretAccount)?.nilIfBlank
        {
            request.setValue("\(settings.headerValuePrefix)\(secret)", forHTTPHeaderField: headerName)
        }

        let (data, _) = try await httpClient.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data)

        let overrideBudget = settings.monthlyBudgetOverrideUSD > 0 ? settings.monthlyBudgetOverrideUSD : nil
        var monthlyBudget = overrideBudget ?? decimal(at: settings.monthlyBudgetPath, in: json)
        var spent = decimal(at: settings.spentPath, in: json)
        let spentToday = decimal(at: settings.spentTodayPath, in: json)
        var remaining = decimal(at: settings.remainingPath, in: json)

        if monthlyBudget == nil, let spent, let remaining {
            monthlyBudget = spent + remaining
        }
        if spent == nil, let monthlyBudget, let remaining {
            spent = max(monthlyBudget - remaining, 0)
        }
        if remaining == nil, let monthlyBudget, let spent {
            remaining = max(monthlyBudget - spent, 0)
        }

        guard let spent else {
            throw ProviderFailure.parsing("REST provider must yield a spend value or enough inputs to derive it.")
        }

        let fallbackCycle = BudgetMath.billingCycle(
            resetDay: settings.fallbackBillingCycleDay,
            now: now
        )
        let resetDate = date(
            at: settings.resetDatePath,
            in: json,
            format: settings.dateFormat
        ) ?? fallbackCycle.end
        let lastPromptCost = decimal(at: settings.lastPromptCostPath, in: json)

        return RawBudgetSnapshot(
            providerID: provider.id,
            providerName: provider.displayName,
            providerKind: provider.kind,
            monthlyBudgetUSD: monthlyBudget,
            spentUSD: spent,
            remainingUSD: remaining,
            billingCycleStart: fallbackCycle.start,
            billingCycleEnd: resetDate,
            spentTodayUSD: spentToday,
            lastPromptCostUSD: lastPromptCost,
            notes: ["Parsed via JSON path mapping."]
        )
    }

    private static func decimal(at path: String, in json: Any) -> Decimal? {
        guard let value = value(at: path, in: json) else {
            return nil
        }

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

    private static func date(at path: String, in json: Any, format: String) -> Date? {
        guard let value = value(at: path, in: json) else {
            return nil
        }

        if let number = value as? NSNumber {
            return parseDate(number.stringValue, format: format)
        }
        if let text = value as? String {
            return parseDate(text, format: format)
        }
        return nil
    }

    private static func parseDate(_ value: String, format: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch format.lowercased() {
        case "unixmilliseconds":
            guard let numeric = Double(trimmed) else { return nil }
            return Date(milliseconds: numeric)
        case "unixseconds":
            guard let numeric = Double(trimmed) else { return nil }
            return Date(timeIntervalSince1970: numeric)
        case "iso8601":
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: trimmed)
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.date(from: trimmed)
        }
    }

    private static func value(at path: String, in json: Any) -> Any? {
        guard let path = path.nilIfBlank else {
            return nil
        }

        var current: Any = json
        for component in path.split(separator: ".").map(String.init) {
            if let index = Int(component), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dictionary = current as? [String: Any], let next = dictionary[component] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    private static func isPublicHost(_ host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if normalized == "localhost" || normalized.hasSuffix(".local") || normalized == "::1"
            || normalized == "0.0.0.0" || normalized == "::" {
            return false
        }
        let address = normalized.split(separator: ".").compactMap({ Int($0) })
        guard address.count == 4,
              address.allSatisfy({ 0...255 ~= $0 }) else {
            return true
        }
        if address[0] == 10 || address[0] == 127 || address[0] == 169 && address[1] == 254
            || address[0] == 192 && address[1] == 168
            || address[0] == 172 && (16...31).contains(address[1]) {
            return false
        }
        return true
    }
}
