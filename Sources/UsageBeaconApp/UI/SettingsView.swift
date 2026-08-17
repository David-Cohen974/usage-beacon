import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

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
                    overviewHero
                    providersSection
                    budgetSchedule
                    displaySection
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
                    BeaconGaugeBar(value: dailyUsageRatio, colors: [BeaconPalette.cyan, BeaconPalette.teal], height: 8)
                    Text(dailyUsageDetail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                }
                .padding(18)
                .beaconCard(colors: [BeaconPalette.cyan, BeaconPalette.teal], cornerRadius: 22)
            } else {
                HStack(spacing: 8) {
                    Text("\(activeProviders.count) active provider\(activeProviders.count == 1 ? "" : "s")")
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
            sectionHeading("Display", subtitle: "Keep the desktop readout useful and unobtrusive.")
            HStack {
                Label("Floating HUD", systemImage: "sparkles.tv")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(BeaconPalette.ink)
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("No connectors yet")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)

                    Text("Start with Cursor Personal if you just want the web UI numbers, or Manual Budget if you want to demo the experience instantly.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)

                    HStack(spacing: 10) {
                        BeaconPill(title: "Cursor Personal", symbol: ProviderKind.cursorPersonal.symbolName, colors: ProviderKind.cursorPersonal.accentColors)
                        BeaconPill(title: "Claude Personal", symbol: ProviderKind.claudePersonal.symbolName, colors: ProviderKind.claudePersonal.accentColors)
                        BeaconPill(title: "Manual Budget", symbol: ProviderKind.manual.symbolName, colors: ProviderKind.manual.accentColors)
                        BeaconPill(title: "Custom REST", symbol: ProviderKind.customREST.symbolName, colors: ProviderKind.customREST.accentColors)
                    }
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

    private var dailyUsageRatio: Double {
        let budgets = activeSnapshots.compactMap(\.perWorkingDayRemainingUSD)
        let remaining = budgets.reduce(Decimal.zero, +)
        guard remaining > 0 else { return 0.35 }
        let spent = totalSpentToday ?? 0
        return min(max((spent / (spent + remaining)).doubleValue, 0), 1)
    }

    private var dailyUsageDetail: String {
        let remaining = activeSnapshots.compactMap(\.perWorkingDayRemainingUSD).reduce(Decimal.zero, +)
        guard remaining > 0 else { return "Today’s live usage is up to date." }
        return "\(currency(remaining)) remaining · On track"
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

                            Toggle("Enabled", isOn: $provider.isEnabled)
                                .toggleStyle(.switch)
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
        }
        .onChange(of: provider) { _, updatedProvider in
            model.updateProvider(updatedProvider)
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
                        title: provider.isEnabled ? "Active" : "Paused",
                        symbol: provider.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill",
                        colors: provider.isEnabled ? [BeaconPalette.cyan, BeaconPalette.teal] : [BeaconPalette.amber, BeaconPalette.coral]
                    )
                }
                    .foregroundStyle(BeaconPalette.ink)

                Text(providerMetadata)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Sync") {
                model.updateProvider(provider)
                model.refresh(providerID: provider.id)
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
        }
    }

    private var providerMetadata: String {
        let source = provider.kind == .manual ? "Manual budget" : provider.kind.title
        guard let updated = snapshot?.lastUpdatedAt else { return source }
        return "\(source) · Updated \(DateFormatter.beaconShortTime.string(from: updated))"
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
                sessionState: model.cursorPersonalSessionState,
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
                sessionState: model.claudePersonalSessionState,
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

private struct CursorPersonalProviderFields: View {
    @Binding var settings: CursorPersonalSettings
    let sessionState: CursorDashboardSessionState
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onCheckSession: () -> Void

    var body: some View {
        SettingsPanel(
            title: "Cursor Personal",
            subtitle: "Mirror the same usage page you already see in Cursor’s web UI."
        ) {
            HStack(spacing: 10) {
                BeaconPill(
                    title: sessionState.description,
                    symbol: sessionState == .connected ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark",
                    colors: sessionState == .connected ? [BeaconPalette.cyan, BeaconPalette.teal] : [BeaconPalette.amber, BeaconPalette.coral]
                )
                Spacer()
                Button("Connect") {
                    onConnect()
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: [BeaconPalette.cyan, BeaconPalette.teal],
                        filled: true
                    )
                )
                Button("Check Session") {
                    onCheckSession()
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: [BeaconPalette.cyan, BeaconPalette.teal],
                        filled: false
                    )
                )
                Button("Disconnect") {
                    onDisconnect()
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: [BeaconPalette.amber, BeaconPalette.coral],
                        filled: false
                    )
                )
            }

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
    let sessionState: ClaudeDashboardSessionState
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onCheckSession: () -> Void

    var body: some View {
        SettingsPanel(
            title: "Claude Personal",
            subtitle: "Read your own Claude usage through a local signed-in web session. No admin API key is needed.",
            colors: ProviderKind.claudePersonal.accentColors
        ) {
            HStack(spacing: 10) {
                BeaconPill(
                    title: sessionState.description,
                    symbol: sessionState == .connected ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark",
                    colors: sessionState == .connected ? [BeaconPalette.cyan, BeaconPalette.teal] : [BeaconPalette.amber, BeaconPalette.coral]
                )
                Spacer()
                Button("Connect") {
                    onConnect()
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: ProviderKind.claudePersonal.accentColors,
                        filled: true
                    )
                )
                Button("Check Session") {
                    onCheckSession()
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: ProviderKind.claudePersonal.accentColors,
                        filled: false
                    )
                )
                Button("Disconnect") {
                    onDisconnect()
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: [BeaconPalette.amber, BeaconPalette.coral],
                        filled: false
                    )
                )
            }

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
