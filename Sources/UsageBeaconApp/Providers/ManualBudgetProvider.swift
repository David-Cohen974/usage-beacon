import Foundation

enum ManualBudgetProvider {
    static func fetch(provider: StoredProvider, now: Date) throws -> RawBudgetSnapshot {
        guard let settings = provider.manual else {
            throw ProviderFailure.misconfigured("Manual provider settings are missing.")
        }

        let cycle = BudgetMath.billingCycle(resetDay: settings.billingCycleDay, now: now)
        let remaining = max(settings.monthlyBudgetUSD - settings.spentUSD, 0)
        let lastPrompt = settings.lastPromptCostUSD > 0 ? settings.lastPromptCostUSD : nil
        let spentToday = settings.spentTodayUSD

        return RawBudgetSnapshot(
            providerID: provider.id,
            providerName: provider.displayName,
            providerKind: provider.kind,
            monthlyBudgetUSD: settings.monthlyBudgetUSD,
            spentUSD: settings.spentUSD,
            remainingUSD: remaining,
            billingCycleStart: cycle.start,
            billingCycleEnd: cycle.end,
            spentTodayUSD: spentToday,
            lastPromptCostUSD: lastPrompt,
            notes: ["Manual entry"]
        )
    }
}
