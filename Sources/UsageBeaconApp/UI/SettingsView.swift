import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private let controlColumns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

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

    private var orderedDisplayWeekdays: [Int] {
        WorkingDayService.orderedWeekdays(startingWith: Calendar.current.firstWeekday)
    }

    var body: some View {
        ZStack {
            BeaconBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    overviewHero
                    controlsGrid
                    calendarCard
                    providersSection
                }
                .padding(24)
            }
        }
        .frame(minWidth: 980, minHeight: 760)
    }

    private var overviewHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Usage cockpit")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)

                    Text("Make budget tracking feel alive.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)

                    Text(heroSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    model.refreshAll()
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: [BeaconPalette.cyan, BeaconPalette.teal],
                        filled: true
                    )
                )
            }

            LazyVGrid(columns: summaryColumns, spacing: 14) {
                BeaconMetricTile(
                    title: "Providers",
                    value: "\(model.configuration.providers.count)",
                    detail: "\(activeProviders.count) active now",
                    colors: [BeaconPalette.cyan, BeaconPalette.teal]
                )
                BeaconMetricTile(
                    title: "Workweek",
                    value: "\(model.configuration.settings.effectiveWorkingDaysPerWeek) days",
                    detail: model.configuration.settings.workingWeekSchedule.shortTitle,
                    colors: [BeaconPalette.amber, BeaconPalette.coral]
                )
                BeaconMetricTile(
                    title: "Refresh",
                    value: "\(model.configuration.settings.refreshIntervalMinutes)m",
                    detail: model.configuration.settings.showFloatingHUD ? "HUD visible" : "HUD hidden",
                    colors: [BeaconPalette.rose, BeaconPalette.amber]
                )
                BeaconMetricTile(
                    title: "Today",
                    value: currency(totalSpentToday),
                    detail: totalSpentToday == nil ? "No live daily data yet" : "Across daily-aware providers",
                    colors: [BeaconPalette.coral, BeaconPalette.rose]
                )
            }
        }
        .padding(26)
        .beaconCard(colors: [BeaconPalette.cyan, BeaconPalette.peach], cornerRadius: 34)
    }

    private var controlsGrid: some View {
        LazyVGrid(columns: controlColumns, spacing: 18) {
            SettingsPanel(
                title: "Live Layer",
                subtitle: "Control the floating HUD and the refresh rhythm."
            ) {
                Toggle(
                    "Show floating HUD",
                    isOn: Binding(
                        get: { model.configuration.settings.showFloatingHUD },
                        set: { model.setShowFloatingHUD($0) }
                    )
                )
                .toggleStyle(.switch)

                ProviderFieldGroup("Refresh cadence") {
                    Stepper(
                        value: Binding(
                            get: { model.configuration.settings.refreshIntervalMinutes },
                            set: { model.setRefreshInterval(minutes: $0) }
                        ),
                        in: 1 ... 60,
                        step: 1
                    ) {
                        Text("Refresh every \(model.configuration.settings.refreshIntervalMinutes) minute\(model.configuration.settings.refreshIntervalMinutes == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(BeaconPalette.ink)
                    }
                }

                HStack(spacing: 10) {
                    Button("Refresh Providers") {
                        model.refreshAll()
                    }
                    .buttonStyle(
                        BeaconActionButtonStyle(
                            colors: [BeaconPalette.cyan, BeaconPalette.teal],
                            filled: true
                        )
                    )

                    Button("Request Calendar Access") {
                        model.requestCalendarAccess()
                    }
                    .buttonStyle(
                        BeaconActionButtonStyle(
                            colors: [BeaconPalette.amber, BeaconPalette.coral],
                            filled: false
                        )
                    )
                }
            }

            SettingsPanel(
                title: "Work Rhythm",
                subtitle: "Tune the month math to your actual schedule."
            ) {
                ProviderFieldGroup("Workweek pattern") {
                    Picker(
                        "Workweek pattern",
                        selection: Binding(
                            get: { model.configuration.settings.workingWeekSchedule },
                            set: { model.setWorkingWeekSchedule($0) }
                        )
                    ) {
                        ForEach(WorkingWeekSchedule.allCases) { schedule in
                            Text(schedule.title).tag(schedule)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if model.configuration.settings.workingWeekSchedule == .custom {
                    ProviderFieldGroup("Working weekdays") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                            ForEach(orderedDisplayWeekdays, id: \.self) { weekday in
                                WeekdaySelectionChip(
                                    title: Calendar.current.shortWeekdaySymbols[weekday - 1],
                                    isSelected: model.configuration.settings.normalizedCustomWorkingWeekdays.contains(weekday)
                                ) {
                                    let isSelected = model.configuration.settings.normalizedCustomWorkingWeekdays.contains(weekday)
                                    model.setCustomWorkingWeekday(weekday, isSelected: !isSelected)
                                }
                            }
                        }
                    }
                } else {
                    ProviderFieldGroup("Working days per week") {
                        Stepper(
                            value: Binding(
                                get: { model.configuration.settings.workingDaysPerWeek },
                                set: { model.setWorkingDaysPerWeek($0) }
                            ),
                            in: 1 ... 7,
                            step: 1
                        ) {
                            Text("\(model.configuration.settings.workingDaysPerWeek) focused day\(model.configuration.settings.workingDaysPerWeek == 1 ? "" : "s")")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(BeaconPalette.ink)
                        }
                    }
                }

                Text("Vacation and holiday calendars only subtract runway on these configured working days.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    BeaconPill(
                        title: DateFormatter.beaconMonth.string(from: Date()),
                        symbol: "calendar",
                        colors: [BeaconPalette.peach, BeaconPalette.amber]
                    )
                    BeaconPill(
                        title: model.configuration.settings.useCalendarAdjustments ? "Calendar-aware" : "Manual-only",
                        symbol: model.configuration.settings.useCalendarAdjustments ? "sparkles" : "hand.raised",
                        colors: model.configuration.settings.useCalendarAdjustments ? [BeaconPalette.cyan, BeaconPalette.teal] : [BeaconPalette.amber, BeaconPalette.coral]
                    )
                    BeaconPill(
                        title: model.configuration.settings.workingWeekSchedule.shortTitle,
                        symbol: "calendar.badge.checkmark",
                        colors: [BeaconPalette.coral, BeaconPalette.rose]
                    )
                }
            }
        }
    }

    private var calendarCard: some View {
        SettingsPanel(
            title: "Calendar Intelligence",
            subtitle: "Use all-day events as vacation or holiday blocks so the daily runway stays realistic."
        ) {
            Toggle(
                "Adjust daily budget by selected holiday or vacation calendars",
                isOn: Binding(
                    get: { model.configuration.settings.useCalendarAdjustments },
                    set: { model.setCalendarAdjustmentsEnabled($0) }
                )
            )
            .toggleStyle(.switch)

            if model.availableCalendars.isEmpty {
                Text("No calendars are loaded yet. Grant access first, then choose which calendars should count as blocked workdays.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(BeaconPalette.surfaceSoft)
                    )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(model.availableCalendars) { calendar in
                        Toggle(
                            isOn: Binding(
                                get: {
                                    model.configuration.settings.selectedCalendarIDs.contains(calendar.id)
                                },
                                set: { model.setCalendarSelected(calendar.id, isSelected: $0) }
                            )
                        ) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: calendar.colorHex))
                                    .frame(width: 12, height: 12)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(calendar.title)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(BeaconPalette.ink)
                                    Text("Counts only on configured working days")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(BeaconPalette.mutedInk)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(BeaconPalette.surfaceSoft)
                        )
                    }
                }
            }
        }
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Providers")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                    Text("Connect vendors, manual budgets, or your own REST feed. Each provider gets its own live runway card and editor.")
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
                            .fill(
                                LinearGradient(
                                    colors: [BeaconPalette.coral, BeaconPalette.amber],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
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
                        BeaconPill(title: "Manual Budget", symbol: ProviderKind.manual.symbolName, colors: ProviderKind.manual.accentColors)
                        BeaconPill(title: "Custom REST", symbol: ProviderKind.customREST.symbolName, colors: ProviderKind.customREST.accentColors)
                    }
                }
                .padding(24)
                .beaconCard(colors: [BeaconPalette.peach, BeaconPalette.coral], cornerRadius: 30)
            } else {
                VStack(alignment: .leading, spacing: 18) {
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

    private var heroSubtitle: String {
        if model.configuration.providers.isEmpty {
            return "Build one bright surface for Cursor, Claude, manual budgets, and anything else that can expose usage data."
        }

        let calendars = model.configuration.settings.selectedCalendarIDs.count
        return "Configured for \(activeProviders.count) active provider\(activeProviders.count == 1 ? "" : "s"), a \(model.configuration.settings.effectiveWorkingDaysPerWeek)-day \(model.configuration.settings.workingWeekSchedule.shortTitle.lowercased()) week, and \(calendars) calendar block\(calendars == 1 ? "" : "s")."
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
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(22)
        .beaconCard(colors: provider.kind.accentColors, cornerRadius: 32)
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

            VStack(alignment: .leading, spacing: 6) {
                Text(provider.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(BeaconPalette.ink)

                Text(provider.kind.description)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    BeaconPill(
                        title: provider.kind.title,
                        symbol: provider.kind.symbolName,
                        colors: provider.kind.accentColors
                    )
                    BeaconPill(
                        title: provider.isEnabled ? "Active" : "Paused",
                        symbol: provider.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill",
                        colors: provider.isEnabled ? [BeaconPalette.cyan, BeaconPalette.teal] : [BeaconPalette.amber, BeaconPalette.coral]
                    )
                }
            }

            Spacer()

            Button("Refresh") {
                model.updateProvider(provider)
                model.refresh(providerID: provider.id)
            }
            .buttonStyle(
                BeaconActionButtonStyle(
                    colors: provider.kind.accentColors,
                    filled: false
                )
            )

            Button(role: .destructive) {
                model.removeProvider(id: provider.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(
                BeaconActionButtonStyle(
                    colors: [BeaconPalette.coral, BeaconPalette.rose],
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
                        value: currency(snapshot.spentTodayUSD),
                        detail: snapshot.lastUpdatedAt.map { "As of \(DateFormatter.beaconShortTime.string(from: $0))" } ?? "Current day",
                        colors: [BeaconPalette.coral, BeaconPalette.rose]
                    )
                    BeaconMetricTile(
                        title: "Last prompt",
                        value: currency(snapshot.lastPromptCostUSD),
                        detail: snapshot.billingCycleEnd.map { "Resets \(DateFormatter.shortDate.string(from: $0))" } ?? "No reset date",
                        colors: [BeaconPalette.rose, BeaconPalette.amber]
                    )
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
