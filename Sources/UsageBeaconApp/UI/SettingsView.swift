import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: UpdaterController

    private var activeProviders: [StoredProvider] {
        model.configuration.providers.filter(\.isEnabled)
    }

    private var activeSnapshots: [ProviderSnapshotState] {
        model.orderedSnapshots.filter(\.isEnabled)
    }

    private var totalSpentToday: Decimal? {
        let values = activeSnapshots.compactMap(\.spentTodayUSD)
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(0, +)
    }

    private var orderedDisplayWeekdays: [Int] { [1, 2, 3, 4, 5, 6, 7] }

    private var configuredWorkingWeekdays: Set<Int> {
        WorkingDayService.workingWeekdayNumbers(
            settings: model.configuration.settings,
            referenceDate: Date(),
            calendar: Calendar.current
        )
    }

    var body: some View {
        ZStack {
            BeaconBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    if let recovery = model.configurationRecovery {
                        configurationRecoveryBanner(recovery)
                    }
                    if let message = model.persistenceErrorMessage {
                        persistenceErrorBanner(message)
                    }
                    overviewHero
                    providersSection
                    budgetSchedule
                    displaySection
                    updatesSection
                }
                .padding(30)
            }
        }
        .frame(minWidth: 980, minHeight: 760)
    }

    private var overviewHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Usage & Budget")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)

                    Text("Track your AI usage and keep your daily spend on target.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                }

                Spacer()

                Button {
                    model.refreshAll()
                } label: {
                    Label("Sync all", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: [BeaconPalette.cyan, BeaconPalette.teal],
                        filled: true
                    )
                )
            }

            if let totalSpentToday {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("TODAY")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(BeaconPalette.mutedInk)
                        Spacer()
                        Text(currency(totalSpentToday))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(BeaconPalette.ink)
                    }
                    if let dailyUsageRatio {
                        BeaconGaugeBar(value: dailyUsageRatio, colors: [BeaconPalette.cyan, BeaconPalette.teal], height: 8)
                    }
                    Text(dailyUsageDetail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                }
                .padding(18)
                .beaconCard(colors: [BeaconPalette.cyan, BeaconPalette.teal], cornerRadius: 22)
            } else {
                HStack(spacing: 8) {
                    Text("\(activeProviders.count) enabled connector\(activeProviders.count == 1 ? "" : "s")")
                    Text("·")
                    Text(workingDaysDescription)
                    Text("·")
                    Text("Auto-refresh every \(model.configuration.settings.refreshIntervalMinutes)m")
                    Text("·")
                    Text("No usage data yet")
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(BeaconPalette.mutedInk)
            }
        }
        .padding(.bottom, 2)
    }

    private var budgetSchedule: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Budget Schedule", subtitle: "Set the working days that shape your daily budget runway.")

            VStack(alignment: .leading, spacing: 12) {
                Text("Working days")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(BeaconPalette.ink)
                HStack(spacing: 10) {
                    ForEach(orderedDisplayWeekdays, id: \.self) { weekday in
                        let selected = configuredWorkingWeekdays.contains(weekday)
                        Button {
                            var weekdays = configuredWorkingWeekdays
                            if selected, weekdays.count > 1 {
                                weekdays.remove(weekday)
                            } else if !selected {
                                weekdays.insert(weekday)
                            }
                            model.setCustomWorkingWeekdays(weekdays)
                        } label: {
                            VStack(spacing: 7) {
                                Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                Circle()
                                    .fill(selected ? BeaconPalette.teal : BeaconPalette.track)
                                    .frame(width: 9, height: 9)
                            }
                            .frame(width: 32, height: 44)
                            .foregroundStyle(selected ? BeaconPalette.ink : BeaconPalette.mutedInk)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? BeaconPalette.teal.opacity(0.14) : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("\(model.configuration.settings.effectiveWorkingDaysPerWeek) days selected. Holidays and vacation only affect these days.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BeaconPalette.surfaceSoft))

            calendarModule
        }
    }

    private var calendarModule: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time Off & Holidays")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                    Text("Exclude holidays and vacation days from your daily budget calculation.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                }
                Spacer()
                if !model.availableCalendars.isEmpty {
                    Toggle("Calendar adjustments", isOn: Binding(get: { model.configuration.settings.useCalendarAdjustments }, set: { model.setCalendarAdjustmentsEnabled($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            if let calendarErrorMessage = model.calendarErrorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BeaconPalette.danger)
                    Text(calendarErrorMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                    Spacer()
                    Button("Dismiss") { model.dismissCalendarError() }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BeaconPalette.danger.opacity(0.1)))
            }
            if model.availableCalendars.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(BeaconPalette.cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(calendarEmptyStateTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(BeaconPalette.ink)
                        Text(calendarEmptyStateDetail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(BeaconPalette.mutedInk)
                    }
                    Spacer(minLength: 8)
                    calendarEmptyStateAction
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BeaconPalette.surfaceSoft))
            } else {
                ForEach(model.availableCalendars) { calendar in
                    Toggle(isOn: Binding(get: { model.configuration.settings.selectedCalendarIDs.contains(calendar.id) }, set: { model.setCalendarSelected(calendar.id, isSelected: $0) })) {
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: calendar.colorHex)).frame(width: 10, height: 10)
                            Text(calendar.title).font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BeaconPalette.surfaceSoft))
    }

    private var calendarEmptyStateTitle: String {
        switch model.calendarAccessState {
        case .notDetermined:
            return "Calendar access is not connected"
        case .fullAccess:
            return "Calendar access is on"
        case .writeOnly:
            return "Calendar access is write-only"
        case .denied:
            return "Calendar access is off"
        case .restricted:
            return "Calendar access is restricted"
        case .unknown:
            return "Calendar status is unavailable"
        }
    }

    private var calendarEmptyStateDetail: String {
        switch model.calendarAccessState {
        case .notDetermined:
            return "Connect your calendar to automatically exclude vacations and holidays."
        case .fullAccess:
            return "Full access was granted, but EventKit returned no calendars. Refresh after Calendar finishes syncing."
        case .writeOnly:
            return "UsageBeacon needs full read access to find vacations and holidays. Change Calendar access in System Settings."
        case .denied:
            return "Allow full Calendar access in System Settings, then return here."
        case .restricted:
            return "macOS or a device policy is preventing UsageBeacon from reading calendars."
        case .unknown:
            return "Check the macOS Calendar permission and try again."
        }
    }

    @ViewBuilder
    private var calendarEmptyStateAction: some View {
        switch model.calendarAccessState {
        case .notDetermined:
            Button(model.isRequestingCalendarAccess ? "Connecting…" : "Connect Calendar") {
                model.requestCalendarAccess()
            }
            .disabled(model.isRequestingCalendarAccess)
            .buttonStyle(BeaconActionButtonStyle(colors: [BeaconPalette.cyan, BeaconPalette.teal], filled: false))
        case .fullAccess, .unknown:
            Button("Refresh Calendars") {
                model.refreshCalendarAccess()
            }
            .buttonStyle(BeaconActionButtonStyle(colors: [BeaconPalette.cyan, BeaconPalette.teal], filled: false))
        case .writeOnly, .denied, .restricted:
            Button("Open System Settings") {
                model.openCalendarPrivacySettings()
            }
            .buttonStyle(BeaconActionButtonStyle(colors: [BeaconPalette.cyan, BeaconPalette.teal], filled: false))
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Display", subtitle: "Choose the glanceable surface that works best for you.")
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.grid.1x2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BeaconPalette.cyan)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Notification Center Widget")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(BeaconPalette.ink)
                        BeaconPill(
                            title: "Ready to add",
                            symbol: "checkmark.circle.fill",
                            colors: [BeaconPalette.cyan, BeaconPalette.teal]
                        )
                    }
                    Text("Open Notification Center, choose Edit Widgets, search for UsageBeacon, then pick a small, medium, or large widget.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            Divider().overlay(BeaconPalette.outline)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Floating HUD", systemImage: "sparkles.tv")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                    Text("Show or hide anytime with \(GlobalHotKeyController.displayName)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                }
                Spacer()
                Toggle("Floating HUD", isOn: Binding(get: { model.configuration.settings.showFloatingHUD }, set: { model.setShowFloatingHUD($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Divider().overlay(BeaconPalette.outline)
            HStack {
                Text("Auto-refresh").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(BeaconPalette.ink)
                Spacer()
                Picker("Auto-refresh", selection: Binding(get: { model.configuration.settings.refreshIntervalMinutes }, set: { model.setRefreshInterval(minutes: $0) })) {
                    ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { minute in
                        Text("Every \(minute) minute\(minute == 1 ? "" : "s")").tag(minute)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BeaconPalette.surfaceSoft))
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Updates", subtitle: "Keep UsageBeacon current without downloading it again by hand.")

            VStack(spacing: 0) {
                settingsRow(
                    title: "Check automatically",
                    detail: "Look for a signed update once a day."
                ) {
                    Toggle(
                        "Check automatically",
                        isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.setAutomaticallyChecksForUpdates($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                Divider().overlay(BeaconPalette.outline)

                settingsRow(
                    title: "Download automatically",
                    detail: "Prepare verified updates in the background and install them at a safe time."
                ) {
                    Toggle(
                        "Download automatically",
                        isOn: Binding(
                            get: { updater.automaticallyDownloadsUpdates },
                            set: { updater.setAutomaticallyDownloadsUpdates($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                Divider().overlay(BeaconPalette.outline)

                settingsRow(
                    title: "Beta updates",
                    detail: "Receive prereleases for testing before they reach everyone."
                ) {
                    Toggle(
                        "Beta updates",
                        isOn: Binding(
                            get: { updater.receivesBetaUpdates },
                            set: { updater.setReceivesBetaUpdates($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                Divider().overlay(BeaconPalette.outline)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("UsageBeacon \(appVersionDescription)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(BeaconPalette.ink)
                        Text("Every update is verified with Sparkle Ed25519 signing and Apple code signing.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(BeaconPalette.mutedInk)
                    }
                    Spacer()
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                    .buttonStyle(
                        BeaconActionButtonStyle(
                            colors: [BeaconPalette.cyan, BeaconPalette.teal],
                            filled: false
                        )
                    )
                }
                .padding(.vertical, 14)
            }
            .padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BeaconPalette.surfaceSoft))
        }
    }

    private func settingsRow<Accessory: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(BeaconPalette.ink)
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
            }
            Spacer()
            accessory()
        }
        .padding(.vertical, 14)
    }

    private var appVersionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Providers")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                    Text("Connect usage sources and budgets.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Menu {
                    ForEach(ProviderKind.allCases) { kind in
                        Button(kind.title) {
                            model.addProvider(kind: kind)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Provider")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [BeaconPalette.cyan, BeaconPalette.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                }
                .menuStyle(.borderlessButton)
            }

            if model.configuration.providers.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Let’s connect your first usage source")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)

                    Text("UsageBeacon starts empty. Choose a service below, sign in, and wait for the status to say Connected before expecting usage data.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)

                    HStack(alignment: .top, spacing: 12) {
                        onboardingStep(number: 1, title: "Choose", detail: "Select Cursor, Claude, or a manual budget.")
                        onboardingStep(number: 2, title: "Sign in", detail: "Complete sign-in in the secure browser window.")
                        onboardingStep(number: 3, title: "Verify", detail: "Wait for the connector to show Connected.")
                    }

                    HStack(spacing: 12) {
                        Button {
                            model.addProviderAndBeginSetup(kind: .cursorPersonal)
                        } label: {
                            Label("Sign in to Cursor", systemImage: ProviderKind.cursorPersonal.symbolName)
                        }
                        .buttonStyle(BeaconActionButtonStyle(colors: ProviderKind.cursorPersonal.accentColors, filled: true))

                        Button {
                            model.addProviderAndBeginSetup(kind: .claudePersonal)
                        } label: {
                            Label("Sign in to Claude", systemImage: ProviderKind.claudePersonal.symbolName)
                        }
                        .buttonStyle(BeaconActionButtonStyle(colors: ProviderKind.claudePersonal.accentColors, filled: false))

                        Button {
                            model.addProvider(kind: .manual)
                        } label: {
                            Label("Add Manual Budget", systemImage: ProviderKind.manual.symbolName)
                        }
                        .buttonStyle(BeaconActionButtonStyle(colors: ProviderKind.manual.accentColors, filled: false))
                    }

                    Label("Your password stays in the service’s own sign-in page. UsageBeacon reuses only the local browser session on this Mac.", systemImage: "lock.shield")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                }
                .padding(24)
                .beaconCard(colors: [BeaconPalette.peach, BeaconPalette.coral], cornerRadius: 30)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.configuration.providers.map(\.id), id: \.self) { providerID in
                        if let binding = model.binding(for: providerID) {
                            ProviderEditorView(
                                model: model,
                                provider: binding,
                                snapshot: model.orderedSnapshots.first(where: { $0.id == providerID })
                            )
                        }
                    }
                }
            }
        }
    }

    private func onboardingStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(BeaconPalette.ink))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(BeaconPalette.ink)
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BeaconPalette.surfaceSoft))
    }

    private var dailyBudgetTotals: (spent: Decimal, remaining: Decimal)? {
        let values = activeSnapshots.compactMap { snapshot -> (Decimal, Decimal)? in
            guard let spent = snapshot.spentTodayUSD,
                  let remaining = snapshot.perWorkingDayRemainingUSD else {
                return nil
            }
            return (spent, remaining)
        }
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(into: (spent: Decimal.zero, remaining: Decimal.zero)) { totals, value in
            totals.spent += value.0
            totals.remaining += value.1
        }
    }

    private var dailyUsageRatio: Double? {
        guard let totals = dailyBudgetTotals else {
            return nil
        }
        guard totals.remaining > 0 else {
            return 1
        }
        let allowance = totals.spent + totals.remaining
        guard allowance > 0 else {
            return nil
        }
        return min(max((totals.spent / allowance).doubleValue, 0), 1)
    }

    private var dailyUsageDetail: String {
        guard let totals = dailyBudgetTotals, let ratio = dailyUsageRatio else {
            return "Today’s spend is available, but a daily budget target is not."
        }
        guard totals.remaining > 0 else {
            return "No daily budget remaining · Needs attention"
        }
        let status = ratio >= 0.85 ? "Needs attention" : ratio >= 0.65 ? "Watch usage" : "On track"
        return "\(currency(totals.remaining)) remaining · \(status)"
    }

    private func configurationRecoveryBanner(_ recovery: ConfigurationRecovery) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(BeaconPalette.danger)
            Text(recovery.message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(BeaconPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Reveal Backup") { model.revealConfigurationRecovery() }
            Button("Dismiss") { model.dismissConfigurationRecovery() }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BeaconPalette.danger.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BeaconPalette.danger.opacity(0.35)))
    }

    private func persistenceErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BeaconPalette.danger)
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(BeaconPalette.ink)
            Spacer()
            Button("Dismiss") { model.dismissPersistenceError() }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BeaconPalette.danger.opacity(0.1)))
    }

    private var workingDaysDescription: String {
        "\(model.configuration.settings.effectiveWorkingDaysPerWeek) working days"
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(BeaconPalette.ink)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(BeaconPalette.mutedInk)
        }
    }

    private func currency(_ value: Decimal?) -> String {
        guard let value else {
            return "n/a"
        }
        return value.formatted(.currency(code: "USD"))
    }
}

private struct ProviderEditorView: View {
    @ObservedObject var model: AppModel
    @Binding var provider: StoredProvider
    let snapshot: ProviderSnapshotState?

    @State private var secret: String = ""
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isExpanded {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        SettingsPanel(
                            title: "Identity",
                            subtitle: "Name it the way you want it to appear in the menu bar and HUD.",
                            colors: provider.kind.accentColors
                        ) {
                            ProviderFieldGroup("Display name") {
                                TextField("Display name", text: $provider.displayName)
                                    .beaconInputChrome()
                            }

                            Toggle("Include in tracking", isOn: $provider.isEnabled)
                                .toggleStyle(.switch)

                            Text("This controls whether UsageBeacon refreshes this connector. It does not mean the account is connected.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(BeaconPalette.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)

                        if let snapshot {
                            snapshotSummary(snapshot)
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }

                    providerSpecificFields

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            model.removeProvider(id: provider.id)
                        } label: {
                            Label("Delete provider", systemImage: "trash")
                        }
                        .buttonStyle(
                            BeaconActionButtonStyle(
                                colors: [BeaconPalette.danger, BeaconPalette.coral],
                                filled: false
                            )
                        )
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BeaconPalette.surfaceSoft))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BeaconPalette.outline, lineWidth: 1))
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isExpanded)
        .task(id: provider.id) {
            secret = model.loadSecret(for: provider.id)
            if provider.kind == .cursorPersonal || provider.kind == .claudePersonal,
               setupStatus != .connected {
                isExpanded = true
            }
        }
        .onChange(of: secret) { _, updatedSecret in
            model.saveSecret(updatedSecret, for: provider.id)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ProviderKindOrb(kind: provider.kind)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(provider.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    BeaconPill(
                        title: setupStatus.title,
                        symbol: setupStatus.symbol,
                        colors: setupStatus.colors
                    )
                }
                    .foregroundStyle(BeaconPalette.ink)

                Text(providerMetadata)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(primaryActionTitle) {
                performPrimaryAction()
            }
            .buttonStyle(
                BeaconActionButtonStyle(
                    colors: provider.kind.accentColors,
                    filled: false
                )
            )

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(BeaconPalette.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(provider.displayName) settings" : "Expand \(provider.displayName) settings")
        }
    }

    private var providerMetadata: String {
        let source = provider.kind == .manual ? "Manual budget" : provider.kind.title
        switch setupStatus {
        case .paused:
            return "\(source) · Tracking is paused"
        case .setupRequired:
            return "\(source) · Not connected yet — complete setup to start syncing"
        case .signInRequired:
            return "\(source) · Not connected — sign in to continue"
        case .waitingForSignIn:
            return "\(source) · Finish signing in in the browser window"
        case .checking:
            return "\(source) · Checking the saved session"
        case .syncing:
            return "\(source) · Reading the latest usage"
        case .connected:
            guard let updated = snapshot?.lastUpdatedAt else {
                return "\(source) · Signed in — waiting for the first sync"
            }
            return "\(source) · Connected · Updated \(DateFormatter.beaconShortTime.string(from: updated))"
        case .ready:
            return "\(source) · Ready to sync"
        case .needsAttention:
            return "\(source) · \(snapshot?.errorMessage ?? "Check this connector’s setup")"
        }
    }

    private var setupStatus: ProviderSetupStatus {
        ProviderSetupStatus.resolve(
            provider: provider,
            snapshot: snapshot,
            cursorSession: model.cursorPersonalSessionState,
            claudeSession: model.claudePersonalSessionState,
            hasSecret: secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        )
    }

    private var primaryActionTitle: String {
        switch provider.kind {
        case .cursorPersonal:
            return model.cursorPersonalSessionState == .connected ? "Sync Now" : "Sign In"
        case .claudePersonal:
            return model.claudePersonalSessionState == .connected ? "Sync Now" : "Sign In"
        case .cursorAdmin, .anthropicAdmin, .manual, .customREST:
            return "Sync Now"
        }
    }

    private func performPrimaryAction() {
        model.updateProvider(provider)
        switch provider.kind {
        case .cursorPersonal where model.cursorPersonalSessionState != .connected:
            isExpanded = true
            model.connectCursorPersonal(using: provider.cursorPersonal?.usagePageURL ?? CursorPersonalSettings().usagePageURL)
        case .claudePersonal where model.claudePersonalSessionState != .connected:
            isExpanded = true
            model.connectClaudePersonal(using: provider.claudePersonal?.usagePageURL ?? ClaudePersonalSettings().usagePageURL)
        case .cursorPersonal, .cursorAdmin, .claudePersonal, .anthropicAdmin, .manual, .customREST:
            model.refresh(providerID: provider.id)
        }
    }

    @ViewBuilder
    private var providerSpecificFields: some View {
        switch provider.kind {
        case .cursorPersonal:
            CursorPersonalProviderFields(
                settings: Binding(
                    get: { provider.cursorPersonal ?? CursorPersonalSettings() },
                    set: { provider.cursorPersonal = $0 }
                ),
                setupStatus: setupStatus,
                snapshot: snapshot,
                onConnect: {
                    model.connectCursorPersonal(
                        using: provider.cursorPersonal?.usagePageURL ?? CursorPersonalSettings().usagePageURL
                    )
                },
                onDisconnect: {
                    model.disconnectCursorPersonal(
                        using: provider.cursorPersonal?.usagePageURL ?? CursorPersonalSettings().usagePageURL
                    )
                },
                onCheckSession: {
                    model.refreshCursorPersonalSessionState(
                        using: provider.cursorPersonal?.usagePageURL ?? CursorPersonalSettings().usagePageURL
                    )
                }
            )
        case .cursorAdmin:
            CursorProviderFields(
                settings: Binding(
                    get: { provider.cursor ?? CursorAdminSettings() },
                    set: { provider.cursor = $0 }
                ),
                secret: $secret
            )
        case .claudePersonal:
            ClaudePersonalProviderFields(
                settings: Binding(
                    get: { provider.claudePersonal ?? ClaudePersonalSettings() },
                    set: { provider.claudePersonal = $0 }
                ),
                setupStatus: setupStatus,
                snapshot: snapshot,
                onConnect: {
                    model.connectClaudePersonal(
                        using: provider.claudePersonal?.usagePageURL ?? ClaudePersonalSettings().usagePageURL
                    )
                },
                onDisconnect: {
                    model.disconnectClaudePersonal(
                        using: provider.claudePersonal?.usagePageURL ?? ClaudePersonalSettings().usagePageURL
                    )
                },
                onCheckSession: {
                    model.refreshClaudePersonalSessionState(
                        using: provider.claudePersonal?.usagePageURL ?? ClaudePersonalSettings().usagePageURL
                    )
                }
            )
        case .anthropicAdmin:
            AnthropicProviderFields(
                settings: Binding(
                    get: { provider.anthropic ?? AnthropicAdminSettings() },
                    set: { provider.anthropic = $0 }
                ),
                secret: $secret
            )
        case .manual:
            ManualProviderFields(
                settings: Binding(
                    get: { provider.manual ?? ManualBudgetSettings() },
                    set: { provider.manual = $0 }
                )
            )
        case .customREST:
            CustomRESTProviderFields(
                settings: Binding(
                    get: { provider.customREST ?? CustomRESTSettings() },
                    set: { provider.customREST = $0 }
                ),
                secret: $secret
            )
        }
    }

    @ViewBuilder
    private func snapshotSummary(_ snapshot: ProviderSnapshotState) -> some View {
        SettingsPanel(
            title: "Live Snapshot",
            subtitle: "A current preview of what this provider is sending into the cockpit.",
            colors: snapshot.accentColors
        ) {
            if let errorMessage = snapshot.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(BeaconPalette.danger)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(BeaconPalette.surfaceSoft)
                    )
            } else {
                if snapshot.usageWindows.isEmpty == false {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(snapshot.usageWindows) { window in
                            BeaconMetricTile(
                                title: window.title,
                                value: formatPercent(window.usedPercent),
                                detail: window.resetsAt.map { "Resets \(DateFormatter.shortDate.string(from: $0))" } ?? "Rolling quota",
                                colors: snapshot.accentColors
                            )
                        }
                    }
                }

                if snapshot.usageWindows.isEmpty || snapshot.monthlyBudgetUSD != nil {
                    LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    BeaconMetricTile(
                        title: "Remaining",
                        value: currency(snapshot.remainingUSD),
                        detail: "Live budget room",
                        colors: snapshot.accentColors
                    )
                    BeaconMetricTile(
                        title: "Spent",
                        value: currency(snapshot.spentUSD),
                        detail: "Current cycle",
                        colors: [BeaconPalette.amber, BeaconPalette.coral]
                    )
                    BeaconMetricTile(
                        title: "Per workday",
                        value: currency(snapshot.perWorkingDayRemainingUSD),
                        detail: snapshot.workingDaysRemaining.map { "\($0) day\($0 == 1 ? "" : "s") left" } ?? "No calendar math",
                        colors: [BeaconPalette.cyan, BeaconPalette.teal]
                    )
                    BeaconMetricTile(
                        title: "Today spent",
                        value: snapshot.providerKind.supportsTodaySpend
                            ? currency(snapshot.spentTodayUSD)
                            : "Not provided",
                        detail: snapshot.providerKind.supportsTodaySpend
                            ? (snapshot.lastUpdatedAt.map { "As of \(DateFormatter.beaconShortTime.string(from: $0))" } ?? "Current day")
                            : "No daily cost in this personal API",
                        colors: [BeaconPalette.coral, BeaconPalette.rose]
                    )
                    BeaconMetricTile(
                        title: "Last prompt",
                        value: snapshot.providerKind.supportsLastPromptCost
                            ? currency(snapshot.lastPromptCostUSD)
                            : "Not provided",
                        detail: snapshot.providerKind.supportsLastPromptCost
                            ? (snapshot.billingCycleEnd.map { "Resets \(DateFormatter.shortDate.string(from: $0))" } ?? "No reset date")
                            : "No per-prompt cost in this API",
                        colors: [BeaconPalette.rose, BeaconPalette.amber]
                    )
                }
                }
            }
        }
    }

    private func currency(_ value: Decimal?) -> String {
        guard let value else {
            return "n/a"
        }
        return value.formatted(.currency(code: "USD"))
    }

    private func formatPercent(_ value: Decimal) -> String {
        let number = value.doubleValue
        if number.rounded() == number {
            return "\(Int(number))%"
        }
        return String(format: "%.1f%%", number)
    }
}

private struct PersonalConnectionControls: View {
    let serviceName: String
    let status: ProviderSetupStatus
    let snapshot: ProviderSnapshotState?
    let colors: [Color]
    let onConnect: () -> Void
    let onCheckSession: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: status.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(status.colors.first ?? BeaconPalette.ink)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                    Text(statusDetail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(status == .needsAttention ? BeaconPalette.danger : BeaconPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(status.colors.first?.opacity(0.10) ?? BeaconPalette.surfaceSoft))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(status.colors.first?.opacity(0.30) ?? BeaconPalette.outline))

            HStack(spacing: 10) {
                if status != .connected && status != .syncing && status != .paused {
                    Button(status == .waitingForSignIn ? "Reopen Sign-In" : "Sign in to \(serviceName)") {
                        onConnect()
                    }
                    .buttonStyle(BeaconActionButtonStyle(colors: colors, filled: true))
                }

                Button("Check Connection") {
                    onCheckSession()
                }
                .buttonStyle(BeaconActionButtonStyle(colors: colors, filled: status == .connected || status == .syncing))

                if status == .connected || status == .syncing || status == .waitingForSignIn {
                    Button("Disconnect") {
                        onDisconnect()
                    }
                    .buttonStyle(BeaconActionButtonStyle(colors: [BeaconPalette.amber, BeaconPalette.coral], filled: false))
                }
            }
        }
    }

    private var statusDetail: String {
        switch status {
        case .setupRequired, .signInRequired:
            return "Not connected yet. Click Sign in to \(serviceName), complete the browser sign-in, then return here."
        case .waitingForSignIn:
            return "Finish signing in in the \(serviceName) browser window. This status changes to Connected automatically."
        case .checking:
            return "Checking whether the saved \(serviceName) browser session is still valid."
        case .syncing:
            return "Signed in successfully. UsageBeacon is reading the latest usage now."
        case .connected:
            if let updated = snapshot?.lastUpdatedAt {
                return "Signed in and syncing correctly. Last usage update: \(DateFormatter.beaconShortTime.string(from: updated))."
            }
            return "Signed in successfully. The first usage sync will start automatically."
        case .needsAttention:
            return snapshot?.errorMessage ?? "UsageBeacon could not verify this connector. Check the connection and try again."
        case .paused:
            return "Tracking is paused. Turn on Include in tracking to resume automatic refreshes."
        case .ready:
            return "Setup is complete and ready for the first sync."
        }
    }
}

private struct CursorPersonalProviderFields: View {
    @Binding var settings: CursorPersonalSettings
    let setupStatus: ProviderSetupStatus
    let snapshot: ProviderSnapshotState?
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onCheckSession: () -> Void

    var body: some View {
        SettingsPanel(
            title: "Cursor Personal",
            subtitle: "Mirror the same usage page you already see in Cursor’s web UI."
        ) {
            PersonalConnectionControls(
                serviceName: "Cursor",
                status: setupStatus,
                snapshot: snapshot,
                colors: ProviderKind.cursorPersonal.accentColors,
                onConnect: onConnect,
                onCheckSession: onCheckSession,
                onDisconnect: onDisconnect
            )

            ProviderFieldGroup("Budget override USD") {
                TextField(
                    "0",
                    value: $settings.monthlyBudgetOverrideUSD,
                    format: .number.precision(.fractionLength(2))
                )
                .beaconInputChrome()
            }

            if settings.monthlyBudgetOverrideUSD > 0 {
                ProviderFieldGroup(
                    "Budget reset day",
                    detail: "Used for the per-working-day runway instead of Cursor's subscription renewal date."
                ) {
                    Stepper(
                        value: $settings.budgetResetDay,
                        in: 1 ... 28
                    ) {
                        Text("Day \(settings.budgetResetDay) of each month")
                    }
                }
            }

            ProviderFieldGroup("Usage page URL", detail: "Only change this if Cursor moves the usage page.") {
                TextField("https://cursor.com/dashboard/usage", text: $settings.usagePageURL)
                    .beaconInputChrome()
            }
        }
    }
}

private struct ClaudePersonalProviderFields: View {
    @Binding var settings: ClaudePersonalSettings
    let setupStatus: ProviderSetupStatus
    let snapshot: ProviderSnapshotState?
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onCheckSession: () -> Void

    var body: some View {
        SettingsPanel(
            title: "Claude Personal",
            subtitle: "Read your own Claude usage through a local signed-in web session. No admin API key is needed.",
            colors: ProviderKind.claudePersonal.accentColors
        ) {
            PersonalConnectionControls(
                serviceName: "Claude",
                status: setupStatus,
                snapshot: snapshot,
                colors: ProviderKind.claudePersonal.accentColors,
                onConnect: onConnect,
                onCheckSession: onCheckSession,
                onDisconnect: onDisconnect
            )

            Text("For organization accounts, an owner may need to enable Organization settings → Usage → Member analytics before Claude shows personal spend.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(BeaconPalette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            ProviderFieldGroup(
                "Budget override USD",
                detail: "Optional. Rolling 5-hour and 7-day percentages work without a dollar budget."
            ) {
                TextField(
                    "0",
                    value: $settings.monthlyBudgetOverrideUSD,
                    format: .number.precision(.fractionLength(2))
                )
                .beaconInputChrome()
            }

            if settings.monthlyBudgetOverrideUSD > 0 {
                ProviderFieldGroup(
                    "Budget reset day",
                    detail: "Used for the monthly dollar runway when a budget override is set."
                ) {
                    Stepper(value: $settings.budgetResetDay, in: 1 ... 28) {
                        Text("Day \(settings.budgetResetDay) of each month")
                    }
                }
            }

            ProviderFieldGroup("Usage page URL", detail: "Only change this if Claude moves Settings → Usage.") {
                TextField("https://claude.ai/settings/usage", text: $settings.usagePageURL)
                    .beaconInputChrome()
            }
        }
    }
}

private struct CursorProviderFields: View {
    @Binding var settings: CursorAdminSettings
    @Binding var secret: String

    var body: some View {
        SettingsPanel(
            title: "Cursor Admin",
            subtitle: "Uses Cursor’s team admin API, not the personal web session path."
        ) {
            ProviderFieldGroup("API key", detail: "Use a Cursor Team API key. User API keys can fail with 'Invalid Team API Key'.") {
                SecureField("crsr_...", text: $secret)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Account email") {
                TextField("you@company.com", text: $settings.accountEmail)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Budget override USD") {
                TextField(
                    "0",
                    value: $settings.monthlyBudgetOverrideUSD,
                    format: .number.precision(.fractionLength(2))
                )
                .beaconInputChrome()
            }

            ProviderFieldGroup("API base URL") {
                TextField("https://api.cursor.com", text: $settings.apiBaseURL)
                    .beaconInputChrome()
            }

            Toggle("Use overall spend, not only on-demand overages", isOn: $settings.useOverallSpend)
                .toggleStyle(.switch)
        }
    }
}

private struct AnthropicProviderFields: View {
    @Binding var settings: AnthropicAdminSettings
    @Binding var secret: String

    var body: some View {
        SettingsPanel(
            title: "Anthropic Admin",
            subtitle: "Track Claude spend from Anthropic’s admin reporting APIs."
        ) {
            ProviderFieldGroup("Admin API key") {
                SecureField("sk-ant-admin...", text: $secret)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Monthly budget USD") {
                TextField(
                    "500",
                    value: $settings.monthlyBudgetUSD,
                    format: .number.precision(.fractionLength(2))
                )
                .beaconInputChrome()
            }

            ProviderFieldGroup("Workspace ID", detail: "Optional workspace filter if you only want part of the account.") {
                TextField("Optional workspace filter", text: $settings.workspaceID)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("API base URL") {
                TextField("https://api.anthropic.com", text: $settings.apiBaseURL)
                    .beaconInputChrome()
            }
        }
    }
}

private struct ManualProviderFields: View {
    @Binding var settings: ManualBudgetSettings

    var body: some View {
        SettingsPanel(
            title: "Manual Budget",
            subtitle: "Perfect for testing, personal tracking, or vendors without an API."
        ) {
            ProviderFieldGroup("Monthly budget USD") {
                TextField(
                    "700",
                    value: $settings.monthlyBudgetUSD,
                    format: .number.precision(.fractionLength(2))
                )
                .beaconInputChrome()
            }

            ProviderFieldGroup("Spent this cycle USD") {
                TextField(
                    "0",
                    value: $settings.spentUSD,
                    format: .number.precision(.fractionLength(2))
                )
                .beaconInputChrome()
            }

            ProviderFieldGroup("Spent today USD") {
                TextField(
                    "0",
                    value: Binding(
                        get: { settings.spentTodayUSD ?? 0 },
                        set: { settings.spentTodayUSD = $0 }
                    ),
                    format: .number.precision(.fractionLength(2))
                )
                .beaconInputChrome()
            }

            ProviderFieldGroup("Last prompt USD") {
                TextField(
                    "0",
                    value: $settings.lastPromptCostUSD,
                    format: .number.precision(.fractionLength(2))
                )
                .beaconInputChrome()
            }

            ProviderFieldGroup("Billing cycle reset day") {
                Stepper(
                    value: $settings.billingCycleDay,
                    in: 1 ... 28
                ) {
                    Text("Resets on day \(settings.billingCycleDay) of the month")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                }
            }
        }
    }
}

private struct CustomRESTProviderFields: View {
    @Binding var settings: CustomRESTSettings
    @Binding var secret: String

    var body: some View {
        SettingsPanel(
            title: "Custom REST",
            subtitle: "Map any JSON endpoint into UsageBeacon without writing app code."
        ) {
            ProviderFieldGroup("Endpoint URL") {
                TextField("https://example.com/usage", text: $settings.endpointURL)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("HTTP method") {
                TextField("GET", text: $settings.httpMethod)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Auth header name") {
                TextField("Authorization", text: $settings.headerName)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Auth prefix") {
                TextField("Bearer ", text: $settings.headerValuePrefix)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Secret value") {
                SecureField("Optional secret or token", text: $secret)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Monthly budget path") {
                TextField("limits.monthly_budget", text: $settings.monthlyBudgetPath)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Spent path") {
                TextField("usage.spent", text: $settings.spentPath)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Spent today path") {
                TextField("usage.today.spent", text: $settings.spentTodayPath)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Remaining path") {
                TextField("usage.remaining", text: $settings.remainingPath)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Reset date path") {
                TextField("billing.next_reset_at", text: $settings.resetDatePath)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Last prompt path") {
                TextField("usage.last_prompt_cost", text: $settings.lastPromptCostPath)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Date format") {
                TextField("iso8601 | unixMilliseconds | unixSeconds", text: $settings.dateFormat)
                    .beaconInputChrome()
            }

            ProviderFieldGroup("Budget override USD") {
                TextField(
                    "0",
                    value: $settings.monthlyBudgetOverrideUSD,
                    format: .number.precision(.fractionLength(2))
                )
                .beaconInputChrome()
            }

            ProviderFieldGroup("Fallback billing cycle day") {
                Stepper(
                    value: $settings.fallbackBillingCycleDay,
                    in: 1 ... 28
                ) {
                    Text("Fallback reset day \(settings.fallbackBillingCycleDay)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                }
            }
        }
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var colors: [Color] = [BeaconPalette.cyan, BeaconPalette.teal]
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        colors: [Color] = [BeaconPalette.cyan, BeaconPalette.teal],
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.colors = colors
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(BeaconPalette.ink)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .beaconCard(colors: colors, cornerRadius: 28)
    }
}

private struct ProviderFieldGroup<Content: View>: View {
    let title: String
    var detail: String? = nil
    let content: Content

    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(BeaconPalette.mutedInk)

            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
    }
}

private struct WeekdaySelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : BeaconPalette.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [BeaconPalette.cyan, BeaconPalette.teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(BeaconPalette.surfaceInteractive)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? BeaconPalette.outline.opacity(0.4) : BeaconPalette.glareStrong, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BeaconInputChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BeaconPalette.surfaceInteractive)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(BeaconPalette.glareStrong, lineWidth: 1)
                    )
            )
    }
}

private extension View {
    func beaconInputChrome() -> some View {
        modifier(BeaconInputChromeModifier())
    }
}
