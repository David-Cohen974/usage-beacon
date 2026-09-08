import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var model: AppModel

    private var activeSnapshots: [ProviderSnapshotState] {
        model.orderedSnapshots.filter(\.isEnabled)
    }

    private var connectedSnapshots: [ProviderSnapshotState] {
        activeSnapshots.filter { setupStatus(for: $0) == .connected }
    }

    private var totalRemaining: Decimal? {
        let values = connectedSnapshots.compactMap(\.remainingUSD)
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(0, +)
    }

    private var totalSpent: Decimal? {
        let values = connectedSnapshots.compactMap(\.spentUSD)
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(0, +)
    }

    private var totalSpentToday: Decimal? {
        let values = connectedSnapshots.compactMap(\.spentTodayUSD)
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(0, +)
    }

    private var earliestReset: Date? {
        connectedSnapshots.compactMap(\.billingCycleEnd).min()
    }

    // A bounded window gives the scroll view a real viewport even when its
    // document contains several providers or long error messages.
    private var menuHeight: CGFloat {
        min(620, max(240, (NSScreen.main?.visibleFrame.height ?? 700) - 48))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label { Text("UsageBeacon").font(.headline) } icon: {
                    BeaconAccentIcon(symbol: "waveform.path.ecg")
                }
                Spacer()
                Button { model.refreshAll() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(activeSnapshots.contains(where: \.isLoading))
                .help("Refresh all providers")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    summary
                    if let message = model.widgetSyncErrorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.orderedSnapshots.isEmpty {
                        Text("No providers yet").font(.headline)
                        Text("Add a provider in Settings to see your usage and remaining budget.")
                            .foregroundStyle(.secondary)
                        ForegroundSettingsButton { Text("Add Provider…") }
                    } else {
                        ForEach(model.orderedSnapshots) { snapshot in
                            Divider()
                            ProviderCardView(snapshot: snapshot, setupStatus: setupStatus(for: snapshot))
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Toggle("Floating HUD", isOn: Binding(
                    get: { model.configuration.settings.showFloatingHUD },
                    set: { model.setShowFloatingHUD($0) }
                ))
                .toggleStyle(.checkbox)
                .help("Show the floating usage panel (\(GlobalHotKeyController.displayName))")
                Spacer()
                ForegroundSettingsButton { Text("Settings…") }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .controlSize(.small)
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .background { BeaconBackdrop() }
        .tint(BeaconPalette.cyan)
        .frame(width: 400, height: menuHeight)
        .transaction { $0.animation = nil }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remaining budget").foregroundStyle(.secondary)
            Text(currency(totalRemaining))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(BeaconPalette.luminousInk)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text("\(connectedSnapshots.count) connected source\(connectedSnapshots.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Cycle spent")
                Spacer()
                Text(currency(totalSpent)).monospacedDigit()
            }
            HStack {
                Text("Today spent")
                Spacer()
                Text(currency(totalSpentToday)).monospacedDigit()
            }
            if let earliestReset {
                Text("Next reset \(DateFormatter.shortDate.string(from: earliestReset))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func setupStatus(for snapshot: ProviderSnapshotState) -> ProviderSetupStatus {
        guard let provider = model.configuration.providers.first(where: { $0.id == snapshot.id }) else {
            return .needsAttention
        }
        return ProviderSetupStatus.resolve(
            provider: provider,
            snapshot: snapshot,
            cursorSession: model.cursorPersonalSessionState,
            claudeSession: model.claudePersonalSessionState,
            hasSecret: snapshot.lastUpdatedAt != nil
        )
    }

    private func currency(_ value: Decimal?) -> String {
        guard let value else {
            return "n/a"
        }
        return value.formatted(.currency(code: "USD"))
    }
}

struct ProviderCardView: View {
    let snapshot: ProviderSnapshotState
    let setupStatus: ProviderSetupStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                BeaconAccentIcon(symbol: snapshot.providerKind.symbolName)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.providerName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)

                    HStack(spacing: 8) {
                        BeaconPill(
                            title: setupStatus.title,
                            symbol: setupStatus.symbol,
                            colors: setupStatus.colors
                        )

                        if snapshot.isLoading {
                            BeaconPill(
                                title: "Updating",
                                symbol: "arrow.triangle.2.circlepath",
                                colors: [BeaconPalette.amber, BeaconPalette.coral]
                            )
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(snapshot.primaryUsageWindow == nil ? "Remaining" : "Usage left")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)

                    Text(headlineValue)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            if setupStatus == .setupRequired || setupStatus == .signInRequired || setupStatus == .waitingForSignIn {
                setupBanner
            } else if let errorMessage = snapshot.errorMessage {
                errorBanner(errorMessage)
            } else {
                if let ratio = snapshot.utilizationRatio {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(snapshot.primaryUsageWindow?.title ?? "Usage pulse")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(BeaconPalette.mutedInk)
                            Spacer()
                            Text(percentUsed(ratio))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(BeaconPalette.ink)
                        }
                        BeaconGaugeBar(value: ratio, colors: snapshot.accentColors)
                    }
                }

                if snapshot.usageWindows.isEmpty == false {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.usageWindows) { window in
                            metricPanel(
                                title: window.title,
                                value: formatPercent(window.usedPercent),
                                detail: window.resetsAt.map {
                                    "Resets \(DateFormatter.shortDate.string(from: $0)) at \(DateFormatter.beaconShortTime.string(from: $0))"
                                } ?? "Rolling quota"
                            )
                        }

                        if snapshot.monthlyBudgetUSD != nil {
                            metricPanel(
                                title: "Monthly remaining",
                                value: currency(snapshot.remainingUSD),
                                detail: snapshot.spentUSD.map { "Spent \(currency($0))" } ?? "Member analytics"
                            )
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        metricPanel(
                            title: "Per workday",
                            value: currency(snapshot.perWorkingDayRemainingUSD),
                            detail: snapshot.workingDayBudgetDetail
                        )
                        metricPanel(
                            title: "Today spent",
                            value: snapshot.providerKind.supportsTodaySpend
                                ? currency(snapshot.spentTodayUSD)
                                : "Not provided",
                            detail: snapshot.providerKind.supportsTodaySpend
                                ? (snapshot.lastUpdatedAt.map {
                                    "As of \(DateFormatter.beaconShortTime.string(from: $0))"
                                } ?? "Current day")
                                : "No daily cost in this personal API"
                        )
                        metricPanel(
                            title: "Last prompt",
                            value: snapshot.providerKind.supportsLastPromptCost
                                ? currency(snapshot.lastPromptCostUSD)
                                : "Not provided",
                            detail: snapshot.providerKind.supportsLastPromptCost
                                ? (snapshot.spentUSD.map { "Spent \(currency($0))" } ?? "No spend yet")
                                : "No per-prompt cost in this API"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let cycleEnd = snapshot.primaryUsageWindow?.resetsAt ?? snapshot.billingCycleEnd {
                        BeaconPill(
                            title: "Resets \(DateFormatter.shortDate.string(from: cycleEnd))",
                            symbol: "calendar.badge.clock",
                            colors: [BeaconPalette.amber, BeaconPalette.peach]
                        )
                    }

                    if let lastUpdatedAt = snapshot.lastUpdatedAt {
                        BeaconPill(
                            title: "Updated \(DateFormatter.beaconShortTime.string(from: lastUpdatedAt))",
                            symbol: "clock",
                            colors: [BeaconPalette.cyan, BeaconPalette.teal]
                        )
                    }
                }

                if snapshot.notes.isEmpty == false {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(Array(snapshot.notes.prefix(3)), id: \.self) { note in
                            Text(note)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(BeaconPalette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(BeaconPalette.surfaceSoft)
                                )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: setupStatus.symbol)
                .foregroundStyle(setupStatus.colors.first ?? BeaconPalette.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text(setupStatus.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(BeaconPalette.ink)
                Text(setupStatus == .waitingForSignIn
                    ? "Finish the browser sign-in. UsageBeacon will update this status automatically."
                    : "This source is added, but it is not connected. Open Settings to finish sign-in.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            ForegroundSettingsButton {
                Text("Finish Setup")
            }
            .buttonStyle(BeaconActionButtonStyle(colors: setupStatus.colors, filled: true))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BeaconPalette.surfaceSoft))
    }

    private func metricPanel(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(value).fontWeight(.medium).monospacedDigit()
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headlineValue: String {
        if let window = snapshot.primaryUsageWindow {
            return formatPercent(max(100 - window.usedPercent, 0))
        }
        return currency(snapshot.remainingUSD)
    }

    private func percentUsed(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))% used"
    }

    private func formatPercent(_ value: Decimal) -> String {
        let number = value.doubleValue
        if number.rounded() == number {
            return "\(Int(number))%"
        }
        return String(format: "%.1f%%", number)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BeaconPalette.danger)
            Text(error)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(BeaconPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BeaconPalette.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BeaconPalette.danger.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private func currency(_ value: Decimal?) -> String {
        guard let value else {
            return "n/a"
        }
        return value.formatted(.currency(code: "USD"))
    }
}

struct FloatingHUDView: View {
    let snapshots: [ProviderSnapshotState]
    @ObservedObject var state: FloatingHUDState
    let appearance: AppAppearance
    let onExpansionChange: (Bool) -> Void

    private var primary: ProviderSnapshotState? {
        snapshots.first(where: { $0.id == state.selectedProviderID }) ?? snapshots.first
    }

    private var collapsedWidth: CGFloat { 220 }
    private var utilization: Double {
        primary?.utilizationRatio ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedRow
            if state.isExpanded, let primary {
                expandedDetails(primary)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(state.isExpanded ? 12 : 8)
        .background(
            RoundedRectangle(cornerRadius: state.isExpanded ? 16 : 12, style: .continuous)
                .fill(BeaconPalette.cardStrong.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: state.isExpanded ? 16 : 12, style: .continuous).stroke(BeaconPalette.outline, lineWidth: 1))
        )
        .shadow(color: BeaconPalette.shadow.opacity(0.55), radius: 8, x: 0, y: 4)
        .frame(width: state.isExpanded ? 250 : collapsedWidth, alignment: .leading)
        .preferredColorScheme(appearance.colorScheme)
    }

    private var collapsedRow: some View {
        VStack(spacing: 2) {
            ForEach(Array(snapshots.prefix(2))) { snapshot in
                Button {
                    select(snapshot)
                } label: {
                    compactProvider(snapshot)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(snapshot.providerName), \(hudPrimaryValue(snapshot)), \(percent(snapshot))")
                .accessibilityHint(state.isExpanded && state.selectedProviderID == snapshot.id ? "Collapses details" : "Shows details")

                if snapshot.id != snapshots.prefix(2).last?.id {
                    Divider()
                        .overlay(BeaconPalette.outline)
                }
            }
        }
    }

    private func compactProvider(_ snapshot: ProviderSnapshotState) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(colors(for: snapshot).first ?? BeaconPalette.cyan)
            Text(snapshot.providerName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(BeaconPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(hudPrimaryValue(snapshot))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(BeaconPalette.ink)
            Text(percent(snapshot))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(BeaconPalette.mutedInk)
        }
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func expandedDetails(_ snapshot: ProviderSnapshotState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(BeaconPalette.outline)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.providerName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                    Text(snapshot.providerKind.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                }
                Spacer()
                Text(hudPrimaryValue(snapshot))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BeaconPalette.ink)
            }
            if let errorMessage = snapshot.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.danger)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                BeaconGaugeBar(value: utilization, colors: hudColors, height: 6)
                HStack {
                    Text(snapshot.perWorkingDayRemainingUSD.map { "\(currency($0))/day" } ?? hudSecondaryValue(snapshot))
                    Spacer()
                    Text(statusText)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(BeaconPalette.mutedInk)
            }
            if snapshots.count > 1 {
                Text("+ \(snapshots.count - 1) more connected source\(snapshots.count == 2 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
            }
        }
        .padding(.top, 8)
    }

    private var hudColors: [Color] {
        guard let primary else { return [BeaconPalette.cyan, BeaconPalette.teal] }
        return colors(for: primary)
    }

    private var statusText: String {
        if primary?.errorMessage != nil { return "Connection error" }
        return utilization >= 0.85 ? "Needs attention" : utilization >= 0.65 ? "Watch usage" : "On track"
    }

    private func currency(_ value: Decimal?) -> String {
        guard let value else {
            return "n/a"
        }
        return value.formatted(.currency(code: "USD"))
    }

    private func hudPrimaryValue(_ snapshot: ProviderSnapshotState) -> String {
        if snapshot.errorMessage != nil {
            return "Error"
        }
        if let window = snapshot.primaryUsageWindow {
            return "\(Int(max(100 - window.usedPercent.doubleValue, 0).rounded()))% left"
        }
        return currency(snapshot.remainingUSD)
    }

    private func hudSecondaryValue(_ snapshot: ProviderSnapshotState) -> String {
        if let window = snapshot.primaryUsageWindow {
            return "\(window.title): \(Int(window.usedPercent.doubleValue.rounded()))% used"
        }
        if snapshot.providerKind.supportsTodaySpend == false {
            return "Cycle spent \(currency(snapshot.spentUSD))"
        }
        return "Today \(currency(snapshot.spentTodayUSD))"
    }

    private func percent(_ snapshot: ProviderSnapshotState) -> String {
        if snapshot.errorMessage != nil { return "!" }
        guard let ratio = snapshot.utilizationRatio else { return "—" }
        return "\(Int((ratio * 100).rounded()))%"
    }

    private func colors(for snapshot: ProviderSnapshotState) -> [Color] {
        guard let ratio = snapshot.utilizationRatio else { return snapshot.accentColors }
        if ratio >= 0.85 { return [BeaconPalette.danger, BeaconPalette.coral] }
        if ratio >= 0.65 { return [BeaconPalette.amber, BeaconPalette.coral] }
        return snapshot.accentColors
    }

    private func select(_ snapshot: ProviderSnapshotState) {
        let shouldCollapse = state.isExpanded && state.selectedProviderID == snapshot.id
        withAnimation(.easeInOut(duration: 0.18)) {
            state.selectedProviderID = snapshot.id
            state.isExpanded = !shouldCollapse
        }
        onExpansionChange(state.isExpanded)
    }
}
