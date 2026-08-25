import AppKit
import Foundation
import SwiftUI
import UsageBeaconShared
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published private(set) var snapshotStates: [UUID: ProviderSnapshotState]
    @Published private(set) var availableCalendars: [CalendarSource] = []
    @Published private(set) var calendarAccessState: CalendarAccessState
    @Published private(set) var isRequestingCalendarAccess = false
    @Published private(set) var calendarErrorMessage: String?
    @Published private(set) var cursorPersonalSessionState: CursorDashboardSessionState
    @Published private(set) var claudePersonalSessionState: ClaudeDashboardSessionState
    @Published private(set) var configurationRecovery: ConfigurationRecovery?
    @Published private(set) var persistenceErrorMessage: String?
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    @Published private(set) var launchAtLoginErrorMessage: String?

    private let configurationStore: ConfigurationStore
    private let secretStore: SecretStoring
    private let httpClient: HTTPClientProtocol
    private let workingDayService: WorkingDayService
    private let floatingPanelController: FloatingPanelController
    private let cursorDashboardSessionController: CursorDashboardSessionController
    private let claudeDashboardSessionController: ClaudeDashboardSessionController
    private let launchAtLoginController: LaunchAtLoginControlling
    private var globalHotKeyController: GlobalHotKeyController?
    private var refreshTimer: Timer?
    private var dayBoundaryTimer: Timer?
    private var applicationActivationObserver: NSObjectProtocol?
    private var workspaceWakeObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var inFlightProviderRefreshes: Set<UUID> = []
    private var lastProviderRefreshAttemptAt: [UUID: Date] = [:]
    private var pendingConfigurationSaveTask: Task<Void, Never>?

    private let maximumAutomaticRetryAttempts = 3
    private let minimumRefreshSpacingSeconds: TimeInterval = 30

    init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        secretStore: SecretStoring = KeychainSecretStore(),
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        workingDayService: WorkingDayService = WorkingDayService(),
        floatingPanelController: FloatingPanelController = FloatingPanelController(),
        cursorDashboardSessionController: CursorDashboardSessionController = .shared,
        claudeDashboardSessionController: ClaudeDashboardSessionController = .shared,
        launchAtLoginController: LaunchAtLoginControlling = LaunchAtLoginController(),
        autoStart: Bool = true
    ) {
        self.configurationStore = configurationStore
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.workingDayService = workingDayService
        self.floatingPanelController = floatingPanelController
        self.cursorDashboardSessionController = cursorDashboardSessionController
        self.claudeDashboardSessionController = claudeDashboardSessionController
        self.launchAtLoginController = launchAtLoginController
        self.calendarAccessState = workingDayService.authorizationState
        self.calendarErrorMessage = nil

        let configuration = configurationStore.load()
        self.configuration = configuration
        self.configurationRecovery = configurationStore.lastRecovery
        self.persistenceErrorMessage = nil
        self.launchAtLoginStatus = launchAtLoginController.status
        self.launchAtLoginErrorMessage = nil
        self.snapshotStates = Dictionary(
            uniqueKeysWithValues: configuration.providers.map {
                ($0.id, ProviderSnapshotState.placeholder(from: $0))
            }
        )
        self.cursorPersonalSessionState = cursorDashboardSessionController.state
        self.claudePersonalSessionState = claudeDashboardSessionController.state

        cursorDashboardSessionController.onStateChange = { [weak self] state in
            guard let self else {
                return
            }
            self.cursorPersonalSessionState = state
            if state == .connected {
                self.refreshAll()
            }
        }

        claudeDashboardSessionController.onStateChange = { [weak self] state in
            guard let self else {
                return
            }
            self.claudePersonalSessionState = state
            if state == .connected {
                self.refreshAll()
            }
        }

        workingDayService.startObservingCalendarChanges { [weak self] in
            guard let self else {
                return
            }

            self.calendarAccessState = self.workingDayService.authorizationState
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

        applicationActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreFloatingHUDAfterSystemEvent()
                self?.refreshLaunchAtLoginStatus()
                await self?.reloadCalendars(refreshStore: true)
            }
        }

        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.restoreFloatingHUDAfterSystemEvent()
                self.scheduleRefreshTimer()
                self.scheduleDayBoundaryTimer()
                await self.performRefreshAll(force: false)
            }
        }

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreFloatingHUDAfterSystemEvent()
            }
        }

        if configuration.providers.isEmpty {
            publishWidgetSnapshot()
        }

        if autoStart {
            synchronizeLaunchAtLoginPreference()
            globalHotKeyController = GlobalHotKeyController { [weak self] in
                self?.toggleFloatingHUD()
            }
            scheduleRefreshTimer()
            scheduleDayBoundaryTimer()
            updateFloatingHUD()
            Task {
                await reloadCalendars(refreshStore: true)
                await refreshCursorPersonalSessionStateIfNeeded()
                await refreshClaudePersonalSessionStateIfNeeded()
                await performRefreshAll(force: false)
            }
        }
    }

    var orderedSnapshots: [ProviderSnapshotState] {
        configuration.providers.map { provider in
            snapshotStates[provider.id] ?? ProviderSnapshotState.placeholder(from: provider)
        }
    }

    @discardableResult
    func addProvider(kind: ProviderKind) -> UUID {
        let provider = StoredProvider(kind: kind)
        configuration.providers.append(provider)
        reconcileSnapshotPlaceholders()
        saveConfiguration()
        updateFloatingHUD()
        return provider.id
    }

    func addProviderAndBeginSetup(kind: ProviderKind) {
        addProvider(kind: kind)
        switch kind {
        case .cursorPersonal:
            connectCursorPersonal(using: CursorPersonalSettings().usagePageURL)
        case .claudePersonal:
            connectClaudePersonal(using: ClaudePersonalSettings().usagePageURL)
        case .cursorAdmin, .anthropicAdmin, .manual, .customREST:
            break
        }
    }

    func updateProvider(_ provider: StoredProvider) {
        guard let index = configuration.providers.firstIndex(where: { $0.id == provider.id }) else {
            return
        }
        configuration.providers[index] = provider
        snapshotStates[provider.id]?.providerName = provider.displayName
        snapshotStates[provider.id]?.providerKind = provider.kind
        snapshotStates[provider.id]?.isEnabled = provider.isEnabled
        saveConfiguration(debounced: true)
        updateFloatingHUD()
    }

    func removeProvider(id: UUID) {
        let secretAccount = configuration.providers.first(where: { $0.id == id })?.secretAccount
        configuration.providers.removeAll { $0.id == id }
        snapshotStates.removeValue(forKey: id)
        if let secretAccount {
            do {
                try secretStore.deleteSecret(account: secretAccount)
            } catch {
                persistenceErrorMessage = "The provider was removed, but its Keychain secret could not be deleted: \(error.localizedDescription)"
            }
        }
        saveConfiguration()
        updateFloatingHUD()
    }

    func loadSecret(for providerID: UUID) -> String {
        guard let provider = configuration.providers.first(where: { $0.id == providerID }) else {
            return ""
        }
        return secretStore.loadSecret(account: provider.secretAccount) ?? ""
    }

    func saveSecret(_ secret: String, for providerID: UUID) {
        guard let provider = configuration.providers.first(where: { $0.id == providerID }) else {
            return
        }
        do {
            if secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try secretStore.deleteSecret(account: provider.secretAccount)
            } else {
                try secretStore.saveSecret(secret, account: provider.secretAccount)
            }
        } catch {
            persistenceErrorMessage = "The Keychain change could not be saved: \(error.localizedDescription)"
        }
    }

    func revealConfigurationRecovery() {
        guard let backupURL = configurationRecovery?.backupURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([backupURL])
    }

    func dismissConfigurationRecovery() {
        configurationRecovery = nil
    }

    func dismissPersistenceError() {
        persistenceErrorMessage = nil
    }

    func setShowFloatingHUD(_ enabled: Bool) {
        configuration.settings.showFloatingHUD = enabled
        saveConfiguration()
        updateFloatingHUD()
    }

    func toggleFloatingHUD() {
        setShowFloatingHUD(!configuration.settings.showFloatingHUD)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        configuration.settings.launchAtLogin = enabled
        saveConfiguration()
        launchAtLoginErrorMessage = nil

        do {
            try launchAtLoginController.setEnabled(enabled)
        } catch {
            launchAtLoginErrorMessage = "Launch at login could not be changed: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
    }

    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    func dismissLaunchAtLoginError() {
        launchAtLoginErrorMessage = nil
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

    func setCustomWorkingWeekdays(_ weekdays: Set<Int>) {
        let normalized = GlobalSettings.normalizedCustomWorkingWeekdays(Array(weekdays))
        configuration.settings.workingWeekSchedule = .custom
        configuration.settings.customWorkingWeekdays = normalized
        configuration.settings.workingDaysPerWeek = normalized.count
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
        guard isRequestingCalendarAccess == false else {
            return
        }
        Task {
            isRequestingCalendarAccess = true
            defer { isRequestingCalendarAccess = false }
            calendarErrorMessage = nil
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(150))
            do {
                calendarAccessState = try await workingDayService.requestAccess()
                await reloadCalendars(refreshStore: true)
                await performRefreshAll(force: true)
            } catch {
                calendarAccessState = workingDayService.authorizationState
                calendarErrorMessage = "Calendar access failed: \(error.localizedDescription)"
            }
        }
    }

    func refreshCalendarAccess() {
        Task {
            calendarErrorMessage = nil
            await reloadCalendars(refreshStore: true)
        }
    }

    func dismissCalendarError() {
        calendarErrorMessage = nil
    }

    func openCalendarPrivacySettings() {
        NSApp.activate(ignoringOtherApps: true)
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ]
        for urlString in urls {
            guard let url = URL(string: urlString) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        calendarErrorMessage = "System Settings could not be opened. Open Privacy & Security → Calendars manually."
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

    func connectClaudePersonal(using pageURL: String) {
        claudeDashboardSessionController.openConnectionWindow(pageURL: pageURL)
    }

    func disconnectClaudePersonal(using pageURL: String) {
        Task {
            await claudeDashboardSessionController.disconnect()
            _ = await claudeDashboardSessionController.refreshSessionState(pageURL: pageURL)
            await performRefreshAll(force: true)
        }
    }

    func refreshClaudePersonalSessionState(using pageURL: String) {
        Task {
            _ = await claudeDashboardSessionController.refreshSessionState(pageURL: pageURL)
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

    private func reloadCalendars(refreshStore: Bool = false) async {
        calendarAccessState = workingDayService.authorizationState
        availableCalendars = workingDayService.availableCalendars(refreshStore: refreshStore)
    }

    private func refreshCursorPersonalSessionStateIfNeeded() async {
        guard let pageURL = configuration.providers.compactMap(\.cursorPersonal?.usagePageURL).first else {
            cursorPersonalSessionState = .unknown
            return
        }
        _ = await cursorDashboardSessionController.refreshSessionState(pageURL: pageURL)
    }

    private func refreshClaudePersonalSessionStateIfNeeded() async {
        guard let pageURL = configuration.providers.compactMap(\.claudePersonal?.usagePageURL).first else {
            claudePersonalSessionState = .unknown
            return
        }
        _ = await claudeDashboardSessionController.refreshSessionState(pageURL: pageURL)
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
        var attemptsUsed = 0
        for attempt in 1 ... maximumAutomaticRetryAttempts {
            attemptsUsed = attempt
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
                    try? await Task.sleep(for: retryDelay(forAttempt: attempt, error: error))
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
            attemptsUsed: attemptsUsed
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
            errorMessage: nil,
            usageWindows: rawSnapshot.usageWindows
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

    private func saveConfiguration(debounced: Bool = false) {
        reconcileSnapshotPlaceholders()
        if debounced {
            pendingConfigurationSaveTask?.cancel()
            pendingConfigurationSaveTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard Task.isCancelled == false else {
                    return
                }
                self?.persistConfiguration()
            }
            return
        }

        pendingConfigurationSaveTask?.cancel()
        pendingConfigurationSaveTask = nil
        persistConfiguration()
    }

    private func persistConfiguration() {
        do {
            try configurationStore.save(configuration)
        } catch {
            persistenceErrorMessage = "Your settings could not be saved: \(error.localizedDescription)"
        }
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
        if let failure = error as? ProviderFailure {
            return failure.isRetryable
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

        if provider.kind == .claudePersonal,
           message.contains("claude usage page did not finish loading") {
            return true
        }

        return false
    }

    private func retryDelay(forAttempt attempt: Int, error: Error) -> Duration {
        if let retryAfter = (error as? ProviderFailure)?.retryAfterSeconds {
            return .milliseconds(Int64(min(max(retryAfter, 0), 300) * 1_000))
        }
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
                await self.reloadCalendars(refreshStore: true)
                await self.performRefreshAll(force: false)
                self.scheduleDayBoundaryTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dayBoundaryTimer = timer
    }

    private func synchronizeLaunchAtLoginPreference() {
        launchAtLoginErrorMessage = nil
        do {
            try launchAtLoginController.setEnabled(configuration.settings.launchAtLogin)
        } catch {
            launchAtLoginErrorMessage = "UsageBeacon could not configure launch at login: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginController.status
    }

    private func restoreFloatingHUDAfterSystemEvent() {
        updateFloatingHUD()

        // AppKit may finish rebuilding Spaces and display geometry shortly after wake.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.updateFloatingHUD()
        }
    }

    private func updateFloatingHUD() {
        let snapshots = orderedSnapshots.filter(\.isEnabled)
        floatingPanelController.update(
            with: snapshots,
            visible: configuration.settings.showFloatingHUD
        )
        publishWidgetSnapshot(from: snapshots)
    }

    private func publishWidgetSnapshot(from snapshots: [ProviderSnapshotState]? = nil) {
        let snapshots = snapshots ?? orderedSnapshots.filter(\.isEnabled)
        let hasLoadedSnapshot = snapshots.contains { $0.lastUpdatedAt != nil }
        guard snapshots.isEmpty || hasLoadedSnapshot else {
            return
        }

        let widgetProviders = snapshots.map { snapshot in
            let primaryValue: String
            let secondaryValue: String
            if snapshot.errorMessage != nil {
                primaryValue = "Needs attention"
                secondaryValue = "Open UsageBeacon to reconnect"
            } else if let window = snapshot.primaryUsageWindow {
                let remaining = Int(max(100 - window.usedPercent.doubleValue, 0).rounded())
                primaryValue = "\(remaining)% left"
                secondaryValue = window.title
            } else if let remaining = snapshot.remainingUSD {
                primaryValue = "\(remaining.formatted(.currency(code: "USD"))) left"
                if let spentToday = snapshot.spentTodayUSD {
                    secondaryValue = "\(spentToday.formatted(.currency(code: "USD"))) today"
                } else if let perDay = snapshot.perWorkingDayRemainingUSD {
                    secondaryValue = "\(perDay.formatted(.currency(code: "USD")))/working day"
                } else {
                    secondaryValue = snapshot.providerKind.title
                }
            } else {
                primaryValue = "Sync needed"
                secondaryValue = snapshot.providerKind.title
            }

            return UsageBeaconWidgetProvider(
                id: snapshot.id,
                name: snapshot.providerName,
                sourceName: snapshot.providerKind.title,
                primaryValue: primaryValue,
                secondaryValue: secondaryValue,
                remainingUSD: snapshot.remainingUSD?.doubleValue,
                spentTodayUSD: snapshot.spentTodayUSD?.doubleValue,
                perWorkingDayUSD: snapshot.perWorkingDayRemainingUSD?.doubleValue,
                utilization: snapshot.utilizationRatio,
                hasError: snapshot.errorMessage != nil
            )
        }

        let newestUpdate = snapshots.compactMap(\.lastUpdatedAt).max() ?? Date()
        try? UsageBeaconWidgetSnapshotStore.save(
            UsageBeaconWidgetSnapshot(updatedAt: newestUpdate, providers: widgetProviders)
        )
        WidgetCenter.shared.reloadTimelines(ofKind: UsageBeaconWidgetData.widgetKind)
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

        if provider.kind == .claudePersonal,
           (
               message.localizedCaseInsensitiveContains("sign in")
                   || message.localizedCaseInsensitiveContains("session expired")
           ) {
            return "Claude Personal needs you to sign in again. Click Connect and enter your Claude credentials."
        }

        if let attemptsUsed,
           attemptsUsed > 1,
           shouldRetry(provider: provider, error: error) {
            return "\(message) UsageBeacon stopped after \(attemptsUsed) attempts and will wait before trying again."
        }

        return message
    }
}
