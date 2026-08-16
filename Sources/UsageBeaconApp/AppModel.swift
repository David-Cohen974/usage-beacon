import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published private(set) var snapshotStates: [UUID: ProviderSnapshotState]
    @Published private(set) var availableCalendars: [CalendarSource] = []
    @Published private(set) var cursorPersonalSessionState: CursorDashboardSessionState

    private let configurationStore: ConfigurationStore
    private let secretStore: SecretStoring
    private let httpClient: HTTPClientProtocol
    private let workingDayService: WorkingDayService
    private let floatingPanelController: FloatingPanelController
    private let cursorDashboardSessionController: CursorDashboardSessionController
    private var refreshTimer: Timer?
    private var dayBoundaryTimer: Timer?
    private var inFlightProviderRefreshes: Set<UUID> = []
    private var lastProviderRefreshAttemptAt: [UUID: Date] = [:]

    private let maximumAutomaticRetryAttempts = 3
    private let minimumRefreshSpacingSeconds: TimeInterval = 30

    init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        secretStore: SecretStoring = KeychainSecretStore(),
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        workingDayService: WorkingDayService = WorkingDayService(),
        floatingPanelController: FloatingPanelController = FloatingPanelController(),
        cursorDashboardSessionController: CursorDashboardSessionController = .shared,
        autoStart: Bool = true
    ) {
        self.configurationStore = configurationStore
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.workingDayService = workingDayService
        self.floatingPanelController = floatingPanelController
        self.cursorDashboardSessionController = cursorDashboardSessionController

        let configuration = configurationStore.load()
        self.configuration = configuration
        self.snapshotStates = Dictionary(
            uniqueKeysWithValues: configuration.providers.map {
                ($0.id, ProviderSnapshotState.placeholder(from: $0))
            }
        )
        self.cursorPersonalSessionState = cursorDashboardSessionController.state

        cursorDashboardSessionController.onStateChange = { [weak self] state in
            guard let self else {
                return
            }
            self.cursorPersonalSessionState = state
            if state == .connected {
                self.refreshAll()
            }
        }

        workingDayService.startObservingCalendarChanges { [weak self] in
            guard let self else {
                return
            }

            self.availableCalendars = self.workingDayService.availableCalendars()
            guard
                self.configuration.settings.useCalendarAdjustments,
                self.configuration.settings.selectedCalendarIDs.isEmpty == false
            else {
                return
            }

            Task { @MainActor [weak self] in
                await self?.performRefreshAll(force: false)
            }
        }

        if autoStart {
            scheduleRefreshTimer()
            scheduleDayBoundaryTimer()
            Task {
                await reloadCalendars()
                await refreshCursorPersonalSessionStateIfNeeded()
                await performRefreshAll(force: false)
            }
        }
    }

    var orderedSnapshots: [ProviderSnapshotState] {
        configuration.providers.map { provider in
            snapshotStates[provider.id] ?? ProviderSnapshotState.placeholder(from: provider)
        }
    }

    func addProvider(kind: ProviderKind) {
        configuration.providers.append(StoredProvider(kind: kind))
        reconcileSnapshotPlaceholders()
        saveConfiguration()
    }

    func updateProvider(_ provider: StoredProvider) {
        guard let index = configuration.providers.firstIndex(where: { $0.id == provider.id }) else {
            return
        }
        configuration.providers[index] = provider
        snapshotStates[provider.id]?.providerName = provider.displayName
        snapshotStates[provider.id]?.providerKind = provider.kind
        snapshotStates[provider.id]?.isEnabled = provider.isEnabled
        saveConfiguration()
        updateFloatingHUD()
    }

    func removeProvider(id: UUID) {
        configuration.providers.removeAll { $0.id == id }
        snapshotStates.removeValue(forKey: id)
        try? secretStore.deleteSecret(account: "usage-beacon-\(id.uuidString)")
        saveConfiguration()
        updateFloatingHUD()
    }

    func loadSecret(for providerID: UUID) -> String {
        secretStore.loadSecret(account: "usage-beacon-\(providerID.uuidString)") ?? ""
    }

    func saveSecret(_ secret: String, for providerID: UUID) {
        let account = "usage-beacon-\(providerID.uuidString)"
        if secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? secretStore.deleteSecret(account: account)
            return
        }
        try? secretStore.saveSecret(secret, account: account)
    }

    func setShowFloatingHUD(_ enabled: Bool) {
        configuration.settings.showFloatingHUD = enabled
        saveConfiguration()
        updateFloatingHUD()
    }

    func setRefreshInterval(minutes: Int) {
        configuration.settings.refreshIntervalMinutes = min(60, max(1, minutes))
        saveConfiguration()
        scheduleRefreshTimer()
    }

    func setWorkingDaysPerWeek(_ days: Int) {
        configuration.settings.workingDaysPerWeek = min(7, max(1, days))
        saveConfiguration()
        refreshAll()
    }

    func setWorkingWeekSchedule(_ schedule: WorkingWeekSchedule) {
        configuration.settings.workingWeekSchedule = schedule
        saveConfiguration()
        refreshAll()
    }

    func setCustomWorkingWeekday(_ weekday: Int, isSelected: Bool) {
        guard (1 ... 7).contains(weekday) else {
            return
        }

        var weekdays = Set(configuration.settings.normalizedCustomWorkingWeekdays)
        if isSelected {
            weekdays.insert(weekday)
        } else if weekdays.count > 1 {
            weekdays.remove(weekday)
        }

        configuration.settings.customWorkingWeekdays = GlobalSettings.normalizedCustomWorkingWeekdays(Array(weekdays))
        saveConfiguration()
        refreshAll()
    }

    func setCalendarAdjustmentsEnabled(_ enabled: Bool) {
        configuration.settings.useCalendarAdjustments = enabled
        saveConfiguration()
        refreshAll()
    }

    func setCalendarSelected(_ calendarID: String, isSelected: Bool) {
        var ids = Set(configuration.settings.selectedCalendarIDs)
        if isSelected {
            ids.insert(calendarID)
        } else {
            ids.remove(calendarID)
        }
        configuration.settings.selectedCalendarIDs = ids.sorted()
        saveConfiguration()
        refreshAll()
    }

    func requestCalendarAccess() {
        Task {
            _ = await workingDayService.requestAccess()
            await reloadCalendars()
            await performRefreshAll(force: true)
        }
    }

    func connectCursorPersonal(using pageURL: String) {
        cursorDashboardSessionController.openConnectionWindow(pageURL: pageURL)
    }

    func disconnectCursorPersonal(using pageURL: String) {
        Task {
            await cursorDashboardSessionController.disconnect()
            _ = await cursorDashboardSessionController.refreshSessionState(pageURL: pageURL)
            await performRefreshAll(force: true)
        }
    }

    func refreshCursorPersonalSessionState(using pageURL: String) {
        Task {
            _ = await cursorDashboardSessionController.refreshSessionState(pageURL: pageURL)
        }
    }

    func refreshAll() {
        Task {
            await performRefreshAll(force: true)
        }
    }

    func refresh(providerID: UUID) {
        Task {
            await performRefresh(providerID: providerID, force: true)
        }
    }

    func binding(for providerID: UUID) -> Binding<StoredProvider>? {
        guard let initialProvider = configuration.providers.first(where: { $0.id == providerID }) else {
            return nil
        }

        return Binding(
            get: {
                self.configuration.providers.first(where: { $0.id == providerID }) ?? initialProvider
            },
            set: { updatedProvider in
                guard self.configuration.providers.contains(where: { $0.id == providerID }) else {
                    return
                }
                self.updateProvider(updatedProvider)
            }
        )
    }

    private func reloadCalendars() async {
        availableCalendars = workingDayService.availableCalendars()
    }

    private func refreshCursorPersonalSessionStateIfNeeded() async {
        guard let pageURL = configuration.providers.compactMap(\.cursorPersonal?.usagePageURL).first else {
            cursorPersonalSessionState = .unknown
            return
        }
        _ = await cursorDashboardSessionController.refreshSessionState(pageURL: pageURL)
    }

    private func performRefreshAll(force: Bool) async {
        for provider in configuration.providers {
            await performRefresh(providerID: provider.id, force: force)
        }
    }

    private func performRefresh(providerID: UUID, force: Bool) async {
        guard let provider = configuration.providers.first(where: { $0.id == providerID }) else {
            return
        }
        guard shouldStartRefresh(for: provider.id, force: force) else {
            return
        }
        inFlightProviderRefreshes.insert(provider.id)
        lastProviderRefreshAttemptAt[provider.id] = Date()
        defer {
            inFlightProviderRefreshes.remove(provider.id)
        }

        var loadingState = snapshotStates[provider.id] ?? .placeholder(from: provider)
        loadingState.providerName = provider.displayName
        loadingState.providerKind = provider.kind
        loadingState.isEnabled = provider.isEnabled
        loadingState.isLoading = provider.isEnabled
        loadingState.errorMessage = nil
        snapshotStates[provider.id] = loadingState

        guard provider.isEnabled else {
            snapshotStates[provider.id]?.isLoading = false
            snapshotStates[provider.id]?.notes = ["Disabled"]
            updateFloatingHUD()
            return
        }

        var finalError: Error?
        for attempt in 1 ... maximumAutomaticRetryAttempts {
            do {
                let rawSnapshot = try await ProviderResolver.fetch(
                    provider: provider,
                    secretStore: secretStore,
                    httpClient: httpClient,
                    now: Date()
                )
                let enriched = enrich(rawSnapshot)
                snapshotStates[provider.id] = enriched
                updateFloatingHUD()
                return
            } catch {
                finalError = error
                if attempt < maximumAutomaticRetryAttempts,
                   shouldRetry(provider: provider, error: error) {
                    try? await Task.sleep(for: retryDelay(forAttempt: attempt))
                    continue
                }
                break
            }
        }

        var failed = snapshotStates[provider.id] ?? .placeholder(from: provider)
        failed.isLoading = false
        failed.errorMessage = userFacingErrorMessage(
            for: provider,
            error: finalError ?? ProviderFailure.network("Unknown refresh failure."),
            attemptsUsed: maximumAutomaticRetryAttempts
        )
        failed.lastUpdatedAt = Date()
        snapshotStates[provider.id] = failed
        updateFloatingHUD()
    }

    private func enrich(_ rawSnapshot: RawBudgetSnapshot) -> ProviderSnapshotState {
        let adjustedRemaining = rawSnapshot.remainingUSD
            ?? rawSnapshot.monthlyBudgetUSD.map { max($0 - rawSnapshot.spentUSD, 0) }
        let workingDaysRemaining = configuration.settings.useCalendarAdjustments
            ? workingDayService.remainingWorkingDays(
                from: Date(),
                until: rawSnapshot.billingCycleEnd,
                selectedCalendarIDs: configuration.settings.selectedCalendarIDs,
                settings: configuration.settings
            )
            : workingDaysUntilCycleEnd(rawSnapshot.billingCycleEnd)
        let perWorkingDay = BudgetMath.remainingPerWorkingDay(
            remainingUSD: adjustedRemaining,
            workingDaysRemaining: workingDaysRemaining
        )

        return ProviderSnapshotState(
            id: rawSnapshot.providerID,
            providerName: rawSnapshot.providerName,
            providerKind: rawSnapshot.providerKind,
            isEnabled: true,
            isLoading: false,
            monthlyBudgetUSD: rawSnapshot.monthlyBudgetUSD,
            spentUSD: rawSnapshot.spentUSD,
            remainingUSD: adjustedRemaining,
            billingCycleEnd: rawSnapshot.billingCycleEnd,
            workingDaysRemaining: workingDaysRemaining,
            perWorkingDayRemainingUSD: perWorkingDay,
            spentTodayUSD: rawSnapshot.spentTodayUSD,
            lastPromptCostUSD: rawSnapshot.lastPromptCostUSD,
            lastUpdatedAt: Date(),
            notes: rawSnapshot.notes,
            errorMessage: nil
        )
    }

    private func workingDaysUntilCycleEnd(_ cycleEnd: Date) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: cycleEnd)
        return WorkingDayService.remainingWorkingDays(
            from: start,
            until: end,
            blockedDays: [],
            settings: configuration.settings,
            calendar: calendar
        )
    }

    private func reconcileSnapshotPlaceholders() {
        for provider in configuration.providers {
            if snapshotStates[provider.id] == nil {
                snapshotStates[provider.id] = .placeholder(from: provider)
            }
        }
        let validIDs = Set(configuration.providers.map(\.id))
        snapshotStates = snapshotStates.reduce(into: [:]) { partialResult, element in
            if validIDs.contains(element.key) {
                partialResult[element.key] = element.value
            }
        }
    }

    private func saveConfiguration() {
        reconcileSnapshotPlaceholders()
        try? configurationStore.save(configuration)
    }

    private func shouldStartRefresh(for providerID: UUID, force: Bool) -> Bool {
        if inFlightProviderRefreshes.contains(providerID) {
            return false
        }
        guard !force else {
            return true
        }
        guard let lastAttemptAt = lastProviderRefreshAttemptAt[providerID] else {
            return true
        }
        return Date().timeIntervalSince(lastAttemptAt) >= minimumRefreshSpacingSeconds
    }

    private func shouldRetry(provider: StoredProvider, error: Error) -> Bool {
        if case ProviderFailure.network = error {
            return true
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("timed out")
            || message.contains("temporarily unavailable")
            || message.contains("could not connect")
            || message.contains("network connection") {
            return true
        }

        if provider.kind == .cursorPersonal,
           message.contains("cursor usage page did not finish loading") {
            return true
        }

        return false
    }

    private func retryDelay(forAttempt attempt: Int) -> Duration {
        switch attempt {
        case 1:
            return .seconds(5)
        case 2:
            return .seconds(15)
        default:
            return .seconds(30)
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(max(1, configuration.settings.refreshIntervalMinutes) * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performRefreshAll(force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func scheduleDayBoundaryTimer() {
        dayBoundaryTimer?.invalidate()

        let calendar = Calendar.current
        let now = Date()
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        let interval = max(60, startOfTomorrow.timeIntervalSince(now) + 5)

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                await self.reloadCalendars()
                await self.performRefreshAll(force: false)
                self.scheduleDayBoundaryTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dayBoundaryTimer = timer
    }

    private func updateFloatingHUD() {
        let snapshots = orderedSnapshots.filter { $0.isEnabled && $0.errorMessage == nil }
        floatingPanelController.update(
            with: snapshots,
            visible: configuration.settings.showFloatingHUD
        )
    }

    private func userFacingErrorMessage(for provider: StoredProvider, error: Error, attemptsUsed: Int? = nil) -> String {
        let message = error.localizedDescription

        if provider.kind == .cursorAdmin,
           message.localizedCaseInsensitiveContains("Invalid Team API Key") {
            return "Cursor rejected this as a Team API key. The key from the User API Keys section is not accepted by this Admin API connector."
        }

        if provider.kind == .cursorPersonal,
           (
               message.localizedCaseInsensitiveContains("sign in")
                   || message.localizedCaseInsensitiveContains("session expired")
           ) {
            return "Cursor personal needs you to sign in again. Click Connect and enter your Cursor credentials."
        }

        if let attemptsUsed,
           attemptsUsed > 1,
           shouldRetry(provider: provider, error: error) {
            return "\(message) UsageBeacon stopped after \(attemptsUsed) attempts and will wait before trying again."
        }

        return message
    }
}
