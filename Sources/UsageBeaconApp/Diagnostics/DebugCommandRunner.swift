import AppKit
import Foundation

enum DebugCommandRunner {
    static func command(from arguments: [String]) -> DebugCommand? {
        if let index = arguments.firstIndex(of: "--debug-cursor-personal") {
            let customURL = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
            return .debugCursorPersonal(pageURLOverride: customURL)
        }
        return nil
    }

    @MainActor
    static func run(_ command: DebugCommand) async {
        switch command {
        case let .debugCursorPersonal(pageURLOverride):
            await runCursorPersonalDiagnostic(pageURLOverride: pageURLOverride)
        }
        NSApplication.shared.terminate(nil)
    }

    @MainActor
    private static func runCursorPersonalDiagnostic(pageURLOverride: String?) async {
        let configuration = ConfigurationStore().load()
        let provider = configuration.providers.first(where: { $0.kind == .cursorPersonal })
        let pageURL = pageURLOverride
            ?? provider?.cursorPersonal?.usagePageURL
            ?? CursorPersonalSettings().usagePageURL
        let sessionController = CursorDashboardSessionController.shared

        var report: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "pageURL": pageURL
        ]

        let sessionState = await sessionController.refreshSessionState(pageURL: pageURL)
        report["sessionState"] = sessionState.description

        if let provider {
            do {
                let snapshot = try await CursorPersonalProvider.fetch(
                    provider: provider,
                    now: Date()
                )
                report["liveProviderSnapshot"] = [
                    "spentUSD": snapshot.spentUSD.description,
                    "remainingUSD": snapshot.remainingUSD?.description ?? "nil",
                    "spentTodayUSD": snapshot.spentTodayUSD?.description ?? "nil",
                    "notes": snapshot.notes
                ]
            } catch {
                report["liveProviderError"] = error.localizedDescription
            }
        }

        do {
            let page = try await sessionController.loadUsagePage(pageURL: pageURL)
            report["pageTitle"] = page.title
            report["resolvedURL"] = page.urlString
            report["looksUnauthenticated"] = page.looksUnauthenticated
            report["looksUsageLike"] = page.looksUsageLike
            report["bodySample"] = String(page.bodyText.prefix(2000))
            report["bodyLength"] = page.bodyText.count
            report["links"] = page.anchorHrefs.filter {
                $0.localizedCaseInsensitiveContains("cursor.com")
                    || $0.localizedCaseInsensitiveContains("cursor.sh")
            }
            report["resourceURLs"] = page.resourceURLs
            report["nextDataSample"] = page.nextDataSample ?? ""
            report["currencyMatches"] = currencyMatches(in: page.bodyText)
            report["apiProbes"] = await apiProbeResults(
                from: page.resourceURLs,
                sessionController: sessionController
            )

            let parsed = try CursorPersonalUsageParser.parse(
                page: page,
                now: Date(),
                budgetOverrideUSD: {
                    guard let value = provider?.cursorPersonal?.monthlyBudgetOverrideUSD, value > 0 else {
                        return nil
                    }
                    return value
                }()
            )
            report["parsed"] = [
                "monthlyBudgetUSD": parsed.monthlyBudgetUSD?.description ?? "nil",
                "spentUSD": parsed.spentUSD.description,
                "remainingUSD": parsed.remainingUSD?.description ?? "nil",
                "billingCycleEnd": ISO8601DateFormatter().string(from: parsed.billingCycleEnd),
                "notes": parsed.notes
            ]
        } catch {
            report["error"] = error.localizedDescription
        }

        if JSONSerialization.isValidJSONObject(report),
           let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        } else {
            print(report)
        }
    }
}

private func currencyMatches(in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: #"\$[0-9][0-9,]*(?:\.\d+)?"#) else {
        return []
    }
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, options: [], range: range)
    return matches.prefix(40).compactMap { match in
        guard let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }
}

@MainActor
private func apiProbeResults(
    from resourceURLs: [String],
    sessionController: CursorDashboardSessionController
) async -> [[String: String]] {
    let interestingPaths = [
        "/api/usage-summary",
        "/api/usage?user=",
        "/api/dashboard/get-plan-info",
        "/api/dashboard/get-monthly-invoice",
        "/api/dashboard/get-daily-spend-by-category"
    ]

    let endpoints = resourceURLs.filter { url in
        interestingPaths.contains { interestingPath in
            url.contains(interestingPath)
        }
    }

    var reports: [[String: String]] = []
    for endpoint in endpoints.prefix(6) {
        do {
            let (data, _) = try await sessionController.authenticatedGET(urlString: endpoint)
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            reports.append([
                "url": endpoint,
                "bodySample": String(body.prefix(2000))
            ])
        } catch {
            reports.append([
                "url": endpoint,
                "error": error.localizedDescription
            ])
        }
    }

    return reports
}

enum DebugCommand {
    case debugCursorPersonal(pageURLOverride: String?)
}
