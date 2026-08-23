import SwiftUI
import UsageBeaconShared
import WidgetKit

private struct UsageBeaconEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageBeaconWidgetSnapshot?
}

private struct UsageBeaconTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageBeaconEntry {
        UsageBeaconEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageBeaconEntry) -> Void) {
        completion(
            UsageBeaconEntry(
                date: Date(),
                snapshot: context.isPreview ? .preview : UsageBeaconWidgetSnapshotStore.load()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageBeaconEntry>) -> Void) {
        let now = Date()
        let entry = UsageBeaconEntry(date: now, snapshot: UsageBeaconWidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

private struct UsageBeaconWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageBeaconEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.providers.isEmpty == false {
                content(snapshot)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.12, blue: 0.20),
                    Color(red: 0.08, green: 0.24, blue: 0.27)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private func content(_ snapshot: UsageBeaconWidgetSnapshot) -> some View {
        switch family {
        case .systemSmall:
            smallContent(snapshot)
        case .systemLarge, .systemExtraLarge:
            providerList(snapshot, limit: 6, showsSummary: true)
        default:
            providerList(snapshot, limit: 3, showsSummary: false)
        }
    }

    private func smallContent(_ snapshot: UsageBeaconWidgetSnapshot) -> some View {
        let primary = snapshot.providers[0]
        let totalValue = summaryValue(snapshot)
        let showsTotal = snapshot.providers.count > 1 && totalValue != nil
        return VStack(alignment: .leading, spacing: 8) {
            widgetHeader(snapshot)
            Spacer(minLength: 0)
            Text(showsTotal ? "Total remaining" : primary.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
            Text(totalValue ?? primary.primaryValue)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.62)
                .lineLimit(1)
            if showsTotal {
                Text("Across \(snapshot.providers.count) tracked sources")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            } else {
                gauge(primary)
                Text(primary.secondaryValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }
        }
    }

    private func providerList(
        _ snapshot: UsageBeaconWidgetSnapshot,
        limit: Int,
        showsSummary: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            widgetHeader(snapshot)
            if showsSummary, let summary = summaryValue(snapshot) {
                HStack(alignment: .firstTextBaseline) {
                    Text(summary)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("remaining")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.64))
                    Spacer()
                }
            }
            ForEach(Array(snapshot.providers.prefix(limit))) { provider in
                providerRow(provider)
            }
            if snapshot.providers.count > limit {
                Text("+ \(snapshot.providers.count - limit) more source\(snapshot.providers.count - limit == 1 ? "" : "s")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private func widgetHeader(_ snapshot: UsageBeaconWidgetSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(Color(red: 0.32, green: 0.82, blue: 0.78))
            Text("UsageBeacon")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Text(snapshot.updatedAt, style: .time)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private func providerRow(_ provider: UsageBeaconWidgetProvider) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor(provider))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 0) {
                    Text(provider.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(provider.secondaryValue)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(provider.primaryValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            gauge(provider)
        }
    }

    @ViewBuilder
    private func gauge(_ provider: UsageBeaconWidgetProvider) -> some View {
        if let utilization = provider.utilization {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(statusColor(provider))
                        .frame(width: proxy.size.width * min(max(utilization, 0), 1))
                }
            }
            .frame(height: 4)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color(red: 0.32, green: 0.82, blue: 0.78))
                Text("UsageBeacon")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.82))
            Text("Open UsageBeacon to add or sync a provider.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryValue(_ snapshot: UsageBeaconWidgetSnapshot) -> String? {
        let remaining = snapshot.providers.compactMap(\.remainingUSD)
        guard remaining.isEmpty == false else { return nil }
        return remaining.reduce(0, +).formatted(.currency(code: "USD"))
    }

    private func statusColor(_ provider: UsageBeaconWidgetProvider) -> Color {
        if provider.hasError { return Color(red: 0.96, green: 0.38, blue: 0.36) }
        guard let utilization = provider.utilization else {
            return Color(red: 0.28, green: 0.68, blue: 0.96)
        }
        if utilization >= 0.85 { return Color(red: 0.96, green: 0.38, blue: 0.36) }
        if utilization >= 0.65 { return Color(red: 0.99, green: 0.73, blue: 0.29) }
        return Color(red: 0.25, green: 0.78, blue: 0.68)
    }
}

private extension UsageBeaconWidgetSnapshot {
    static let preview = UsageBeaconWidgetSnapshot(
        providers: [
            UsageBeaconWidgetProvider(
                id: UUID(),
                name: "Cursor Personal",
                sourceName: "Cursor Personal",
                primaryValue: "$482 left",
                secondaryValue: "$21 today",
                remainingUSD: 482,
                spentTodayUSD: 21,
                perWorkingDayUSD: 26,
                utilization: 0.31,
                hasError: false
            ),
            UsageBeaconWidgetProvider(
                id: UUID(),
                name: "Claude Personal",
                sourceName: "Claude Personal",
                primaryValue: "64% left",
                secondaryValue: "7-day usage",
                remainingUSD: nil,
                spentTodayUSD: nil,
                perWorkingDayUSD: nil,
                utilization: 0.36,
                hasError: false
            )
        ]
    )
}

struct UsageBeaconBudgetWidget: Widget {
    let kind = UsageBeaconWidgetData.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageBeaconTimelineProvider()) { entry in
            UsageBeaconWidgetView(entry: entry)
        }
        .configurationDisplayName("Usage budgets")
        .description("See remaining AI budget and quota usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct UsageBeaconWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageBeaconBudgetWidget()
    }
}
