import Foundation

enum ProviderResolver {
    static func fetch(
        provider: StoredProvider,
        secretStore: SecretStoring,
        httpClient: HTTPClientProtocol,
        now: Date
    ) async throws -> RawBudgetSnapshot {
        switch provider.kind {
        case .cursorPersonal:
            return try await CursorPersonalProvider.fetch(
                provider: provider,
                now: now
            )
        case .claudePersonal:
            return try await ClaudePersonalProvider.fetch(
                provider: provider,
                now: now
            )
        case .manual:
            return try ManualBudgetProvider.fetch(provider: provider, now: now)
        case .cursorAdmin:
            return try await CursorAdminProvider.fetch(
                provider: provider,
                secretStore: secretStore,
                httpClient: httpClient,
                now: now
            )
        case .anthropicAdmin:
            return try await AnthropicAdminProvider.fetch(
                provider: provider,
                secretStore: secretStore,
                httpClient: httpClient,
                now: now
            )
        case .customREST:
            return try await CustomRESTProvider.fetch(
                provider: provider,
                secretStore: secretStore,
                httpClient: httpClient,
                now: now
            )
        }
    }
}
