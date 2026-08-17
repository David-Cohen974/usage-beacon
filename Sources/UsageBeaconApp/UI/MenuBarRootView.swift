import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var model: AppModel

    private var activeSnapshots: [ProviderSnapshotState] {
        model.orderedSnapshots.filter(\.isEnabled)
    }

    private var totalRemaining: Decimal? {
        let values = activeSnapshots.compactMap(\.remainingUSD)
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(0, +)
    }

    private var totalSpent: Decimal? {
        let values = activeSnapshots.compactMap(\.spentUSD)
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(0, +)
    }

    private var totalSpentToday: Decimal? {
        let values = activeSnapshots.compactMap(\.spentTodayUSD)
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(0, +)
    }

    private var earliestReset: Date? {
        activeSnapshots.compactMap(\.billingCycleEnd).min()
    }

    var body: some View {
        ZStack {
            BeaconBackdrop()

            VStack(alignment: .leading, spacing: 16) {
                heroCard
                snapshotsSection
                footerBar
            }
            .padding(16)
        }
        .frame(width: 388)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)

                    Text("Protect the runway.")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(heroSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    model.refreshAll()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: [BeaconPalette.cyan, BeaconPalette.teal],
                        filled: true
                    )
                )
            }

            HStack(spacing: 8) {
                BeaconPill(
                    title: "\(activeSnapshots.count) live source\(activeSnapshots.count == 1 ? "" : "s")",
                    symbol: "waveform.path.ecg",
                    colors: [BeaconPalette.cyan, BeaconPalette.teal]
                )
                if let earliestReset {
                    BeaconPill(
                        title: "Resets \(DateFormatter.shortDate.string(from: earliestReset))",
                        symbol: "calendar",
                        colors: [BeaconPalette.amber, BeaconPalette.coral]
                    )
                }
            }

            HStack(spacing: 8) {
                BeaconMetricTile(
                    title: "Remaining",
                    value: currency(totalRemaining),
                    detail: activeSnapshots.isEmpty ? "Connect a source" : "Across active providers",
                    colors: [BeaconPalette.cyan, BeaconPalette.teal]
                )
                BeaconMetricTile(
                    title: "Spent",
                    value: currency(totalSpent),
                    detail: DateFormatter.beaconMonth.string(from: Date()),
                    colors: [BeaconPalette.amber, BeaconPalette.coral]
                )
                BeaconMetricTile(
                    title: "Today",
                    value: currency(totalSpentToday),
                    detail: totalSpentToday == nil ? "No live daily data yet" : "Across daily-aware providers",
                    colors: [BeaconPalette.rose, BeaconPalette.amber]
                )
            }
        }
        .padding(18)
        .beaconCard(colors: [BeaconPalette.cyan, BeaconPalette.peach], cornerRadius: 32)
    }

    @ViewBuilder
    private var snapshotsSection: some View {
        if model.orderedSnapshots.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("No providers yet")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(BeaconPalette.ink)

                Text("Start with Cursor Personal for a zero-admin setup, or add a manual budget to test the HUD immediately.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsLink {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Open Settings")
                    }
                }
                .buttonStyle(
                    BeaconActionButtonStyle(
                        colors: [BeaconPalette.coral, BeaconPalette.amber],
                        filled: true
                    )
                )
            }
            .padding(18)
            .beaconCard(colors: [BeaconPalette.peach, BeaconPalette.coral], cornerRadius: 30)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.orderedSnapshots) { snapshot in
                        ProviderCardView(snapshot: snapshot)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(maxHeight: 450)
        }
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.configuration.settings.showFloatingHUD ? "sparkles.tv.fill" : "sparkles.tv")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BeaconPalette.ink)

                Toggle(
                    "Floating HUD",
                    isOn: Binding(
                        get: { model.configuration.settings.showFloatingHUD },
                        set: { model.setShowFloatingHUD($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)

                Text("Floating HUD")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(BeaconPalette.ink)
            }

            Spacer()

            SettingsLink {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(
                BeaconActionButtonStyle(
                    colors: [BeaconPalette.cyan, BeaconPalette.teal],
                    filled: false
                )
            )

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(
                BeaconActionButtonStyle(
                    colors: [BeaconPalette.coral, BeaconPalette.amber],
                    filled: false
                )
            )
        }
        .padding(14)
        .beaconCard(colors: [BeaconPalette.peach, BeaconPalette.cyan], cornerRadius: 24)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5 ..< 12:
            return "Good morning"
        case 12 ..< 18:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private var heroSubtitle: String {
        if activeSnapshots.isEmpty {
            return "Wire your budgets into one place and keep the month visually under control."
        }

        if let totalRemaining, totalRemaining > 0 {
            return "You still have \(currency(totalRemaining)) left to spend before the cycle flips."
        }

        return "Every connected budget is out of visible remaining runway. Time to triage."
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ProviderKindOrb(kind: snapshot.providerKind)

                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.providerName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(BeaconPalette.ink)

                    HStack(spacing: 8) {
                        BeaconPill(
                            title: snapshot.providerKind.title,
                            symbol: snapshot.providerKind.symbolName,
                            colors: snapshot.accentColors
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

            if let errorMessage = snapshot.errorMessage {
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
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                        spacing: 10
                    ) {
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
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        metricPanel(
                            title: "Per workday",
                            value: currency(snapshot.perWorkingDayRemainingUSD),
                            detail: snapshot.workingDaysRemaining.map {
                                "\($0) day\($0 == 1 ? "" : "s") left"
                            } ?? "No calendar math"
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

                HStack {
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
        .padding(16)
        .beaconCard(colors: snapshot.accentColors, cornerRadius: 28)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: snapshot)
    }

    private func metricPanel(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(BeaconPalette.mutedInk)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(BeaconPalette.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(BeaconPalette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BeaconPalette.cardStrong)
        )
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
    let onExpansionChange: (Bool) -> Void
    @State private var isExpanded = false
    @State private var selectedProviderID: UUID?

    private var primary: ProviderSnapshotState? {
        snapshots.first(where: { $0.id == selectedProviderID }) ?? snapshots.first
    }

    private var collapsedWidth: CGFloat { 220 }
    private var utilization: Double {
        primary?.utilizationRatio ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedRow
            if isExpanded, let primary {
                expandedDetails(primary)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(isExpanded ? 12 : 8)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 12, style: .continuous)
                .fill(BeaconPalette.cardStrong.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: isExpanded ? 16 : 12, style: .continuous).stroke(BeaconPalette.outline, lineWidth: 1))
        )
        .shadow(color: BeaconPalette.shadow.opacity(0.55), radius: 8, x: 0, y: 4)
        .frame(width: isExpanded ? 250 : collapsedWidth, alignment: .leading)
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
            BeaconGaugeBar(value: utilization, colors: hudColors, height: 6)
            HStack {
                Text(snapshot.perWorkingDayRemainingUSD.map { "\(currency($0))/day" } ?? hudSecondaryValue(snapshot))
                Spacer()
                Text(statusText)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(BeaconPalette.mutedInk)
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
        utilization >= 0.85 ? "Needs attention" : utilization >= 0.65 ? "Watch usage" : "On track"
    }

    private func currency(_ value: Decimal?) -> String {
        guard let value else {
            return "n/a"
        }
        return value.formatted(.currency(code: "USD"))
    }

    private func hudPrimaryValue(_ snapshot: ProviderSnapshotState) -> String {
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
        let shouldCollapse = isExpanded && selectedProviderID == snapshot.id
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedProviderID = snapshot.id
            isExpanded = !shouldCollapse
        }
        onExpansionChange(isExpanded)
    }
}
