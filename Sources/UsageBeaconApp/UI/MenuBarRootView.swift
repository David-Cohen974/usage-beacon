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
                    Text("Remaining")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BeaconPalette.mutedInk)

                    Text(currency(snapshot.remainingUSD))
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
                            Text("Usage pulse")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(BeaconPalette.mutedInk)
                            Spacer()
                            Text("\(Int(ratio * 100))% used")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(BeaconPalette.ink)
                        }
                        BeaconGaugeBar(value: ratio, colors: snapshot.accentColors)
                    }
                }

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
                        value: currency(snapshot.spentTodayUSD),
                        detail: snapshot.lastUpdatedAt.map {
                            "As of \(DateFormatter.beaconShortTime.string(from: $0))"
                        } ?? "Current day"
                    )
                    metricPanel(
                        title: "Last prompt",
                        value: currency(snapshot.lastPromptCostUSD),
                        detail: snapshot.spentUSD.map { "Spent \(currency($0))" } ?? "No spend yet"
                    )
                }

                HStack {
                    if let cycleEnd = snapshot.billingCycleEnd {
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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(BeaconPalette.cardStrong.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(BeaconPalette.glareStrong, lineWidth: 1)
                )
                .shadow(color: BeaconPalette.shadow, radius: 22, x: 0, y: 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("UsageBeacon")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(BeaconPalette.ink)
                        Text("Live monthly runway")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(BeaconPalette.mutedInk)
                    }
                    Spacer()
                    BeaconPill(title: "Live", symbol: "bolt.fill", colors: [BeaconPalette.cyan, BeaconPalette.teal])
                }

                ForEach(snapshots) { snapshot in
                    HStack(spacing: 10) {
                        ProviderKindOrb(kind: snapshot.providerKind)
                            .scaleEffect(0.72)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.providerName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(BeaconPalette.ink)
                            Text(snapshot.providerKind.title)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(BeaconPalette.mutedInk)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(currency(snapshot.remainingUSD))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(BeaconPalette.ink)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("Today \(currency(snapshot.spentTodayUSD))")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(BeaconPalette.mutedInk)
                                .monospacedDigit()
                            if let perDay = snapshot.perWorkingDayRemainingUSD {
                                Text("\(currency(perDay))/day")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(BeaconPalette.mutedInk)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(BeaconPalette.surfaceSoft)
                    )
                }
            }
            .padding(14)
        }
        .frame(width: 312)
    }

    private func currency(_ value: Decimal?) -> String {
        guard let value else {
            return "n/a"
        }
        return value.formatted(.currency(code: "USD"))
    }
}
