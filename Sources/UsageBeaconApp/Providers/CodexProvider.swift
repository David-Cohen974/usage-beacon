import Foundation

enum CodexProvider {
    static func fetch(
        provider: StoredProvider,
        now: Date
    ) async throws -> RawBudgetSnapshot {
        guard let settings = provider.codex else {
            throw ProviderFailure.misconfigured("Codex settings are missing.")
        }

        let executablePath = try resolveExecutablePath(settings.executablePath)
        let responseData = try await Task.detached(priority: .utility) {
            let session = CodexAppServerSession()
            return try session.readRateLimits(executablePath: executablePath)
        }.value

        return try parseRateLimitsResponse(
            responseData,
            provider: provider,
            now: now
        )
    }

    static func parseRateLimitsResponse(
        _ data: Data,
        provider: StoredProvider,
        now: Date
    ) throws -> RawBudgetSnapshot {
        let envelope: CodexJSONRPCResponse
        do {
            envelope = try JSONDecoder().decode(CodexJSONRPCResponse.self, from: data)
        } catch {
            throw ProviderFailure.parsing("Codex returned an unreadable rate-limit response.")
        }

        if let rpcError = envelope.error {
            let message = rpcError.message.nilIfBlank ?? "Codex could not read this account's usage limits."
            if message.localizedCaseInsensitiveContains("login")
                || message.localizedCaseInsensitiveContains("sign in")
                || message.localizedCaseInsensitiveContains("authentication") {
                throw ProviderFailure.authentication(
                    "Codex is not signed in. Sign in with the Codex app or CLI, then sync again."
                )
            }
            throw ProviderFailure.parsing("Codex could not read usage limits: \(message)")
        }

        guard let response = envelope.result else {
            throw ProviderFailure.parsing("Codex did not return a rate-limit snapshot.")
        }

        return try mapRateLimits(response, provider: provider, now: now)
    }

    static func mapRateLimits(
        _ response: CodexRateLimitsResponse,
        provider: StoredProvider,
        now: Date
    ) throws -> RawBudgetSnapshot {
        let entries: [(key: String, snapshot: CodexRateLimitSnapshot)]
        if let buckets = response.rateLimitsByLimitId, buckets.isEmpty == false {
            entries = buckets
                .map { (key: $0.key, snapshot: $0.value) }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        } else {
            entries = [(key: "codex", snapshot: response.rateLimits)]
        }

        let prefixesBuckets = entries.count > 1
        var usageWindows: [UsageWindowSnapshot] = []

        for entry in entries {
            let bucketName = displayName(for: entry)
            let prefix = prefixesBuckets ? "\(bucketName) · " : ""
            var primaryTitle: String?

            if let primary = entry.snapshot.primary {
                let title = prefix + windowTitle(primary, fallback: "Primary window")
                primaryTitle = title
                usageWindows.append(windowSnapshot(primary, title: title))
            }

            if let secondary = entry.snapshot.secondary {
                var title = prefix + windowTitle(secondary, fallback: "Secondary window")
                if title == primaryTitle {
                    title += " (secondary)"
                }
                usageWindows.append(windowSnapshot(secondary, title: title))
            }

            if let individualLimit = entry.snapshot.individualLimit {
                let title = prefix + "Spend control"
                usageWindows.append(
                    UsageWindowSnapshot(
                        kind: .modelSpecific,
                        title: title,
                        usedPercent: Decimal(min(max(100 - individualLimit.remainingPercent, 0), 100)),
                        resetsAt: date(fromUnixSeconds: individualLimit.resetsAt)
                    )
                )
            }
        }

        guard usageWindows.isEmpty == false else {
            throw ProviderFailure.parsing(
                "Codex is connected, but it did not expose a rolling usage or spend-control limit for this account."
            )
        }

        let resetDates = usageWindows.compactMap(\.resetsAt)
        let billingCycleEnd = resetDates.max() ?? BudgetMath.calendarMonthCycle(now: now).end
        var notes = [
            "Reading Codex usage locally through the Codex app-server and your existing sign-in. No API key is stored.",
            "Codex reports rolling quota percentages, not token counts or per-prompt dollar cost."
        ]

        let planNames = Set(entries.compactMap { $0.snapshot.planType?.nilIfBlank })
        if planNames.count == 1, let planName = planNames.first {
            notes.append("Codex plan: \(humanized(planName)).")
        }
        if let resetCredits = response.rateLimitResetCredits, resetCredits.availableCount > 0 {
            notes.append(
                "Codex reports \(resetCredits.availableCount) available usage reset credit\(resetCredits.availableCount == 1 ? "" : "s")."
            )
        }

        return RawBudgetSnapshot(
            providerID: provider.id,
            providerName: provider.displayName,
            providerKind: provider.kind,
            monthlyBudgetUSD: nil,
            spentUSD: 0,
            remainingUSD: nil,
            billingCycleStart: nil,
            billingCycleEnd: billingCycleEnd,
            spentTodayUSD: nil,
            lastPromptCostUSD: nil,
            notes: notes,
            usageWindows: usageWindows
        )
    }

    static func resolveExecutablePath(
        _ configuredPath: String,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        if let configured = configuredPath.nilIfBlank {
            let expanded = NSString(string: configured).expandingTildeInPath
            guard fileManager.isExecutableFile(atPath: expanded) else {
                throw ProviderFailure.misconfigured(
                    "The configured Codex executable is missing or cannot be run: \(expanded)"
                )
            }
            return expanded
        }

        var candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { directory in
                String(directory) + "/codex"
            })
        }

        var seen = Set<String>()
        if let executable = candidates.first(where: { candidate in
            seen.insert(candidate).inserted && fileManager.isExecutableFile(atPath: candidate)
        }) {
            return executable
        }

        throw ProviderFailure.misconfigured(
            "Codex was not found. Install the Codex app or CLI, or set its executable path in this provider."
        )
    }

    private static func displayName(
        for entry: (key: String, snapshot: CodexRateLimitSnapshot)
    ) -> String {
        if let name = entry.snapshot.limitName?.nilIfBlank {
            return name
        }
        if let identifier = entry.snapshot.limitId?.nilIfBlank {
            return humanized(identifier)
        }
        return humanized(entry.key)
    }

    private static func windowSnapshot(
        _ window: CodexRateLimitWindow,
        title: String
    ) -> UsageWindowSnapshot {
        UsageWindowSnapshot(
            kind: windowKind(durationMinutes: window.windowDurationMins),
            title: title,
            usedPercent: min(max(window.usedPercent, 0), 100),
            resetsAt: window.resetsAt.flatMap(date(fromUnixSeconds:))
        )
    }

    private static func windowKind(durationMinutes: Int64?) -> UsageWindowKind {
        switch durationMinutes {
        case 300:
            return .fiveHour
        case 10_080:
            return .sevenDay
        default:
            return .modelSpecific
        }
    }

    private static func windowTitle(
        _ window: CodexRateLimitWindow,
        fallback: String
    ) -> String {
        guard let minutes = window.windowDurationMins, minutes > 0 else {
            return fallback
        }
        if minutes.isMultiple(of: 1_440) {
            return "\(minutes / 1_440)-day window"
        }
        if minutes.isMultiple(of: 60) {
            return "\(minutes / 60)-hour window"
        }
        return "\(minutes)-minute window"
    }

    private static func date(fromUnixSeconds value: Int64) -> Date? {
        guard value > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }

    private static func humanized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

struct CodexJSONRPCResponse: Decodable {
    var result: CodexRateLimitsResponse?
    var error: CodexJSONRPCError?
}

struct CodexJSONRPCError: Decodable {
    var code: Int?
    var message: String
}

struct CodexRateLimitsResponse: Decodable {
    var rateLimits: CodexRateLimitSnapshot
    var rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
    var rateLimitResetCredits: CodexRateLimitResetCredits?
}

struct CodexRateLimitResetCredits: Decodable {
    var availableCount: Int
}

struct CodexRateLimitSnapshot: Decodable {
    var limitId: String?
    var limitName: String?
    var planType: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?
    var individualLimit: CodexSpendControlLimit?
}

struct CodexRateLimitWindow: Decodable {
    var usedPercent: Decimal
    var windowDurationMins: Int64?
    var resetsAt: Int64?
}

struct CodexSpendControlLimit: Decodable {
    var remainingPercent: Int
    var resetsAt: Int64
}

private final class CodexAppServerSession: @unchecked Sendable {
    private let lock = NSLock()
    private let completion = DispatchSemaphore(value: 0)
    private var readBuffer = Data()
    private var responseData: Data?
    private var responseError: Error?
    private var isComplete = false
    private var didRequestRateLimits = false
    private var inputHandle: FileHandle?

    func readRateLimits(
        executablePath: String,
        timeout: TimeInterval = 12
    ) throws -> Data {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        inputHandle = inputPipe.fileHandleForWriting

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] terminatedProcess in
            guard terminatedProcess.terminationStatus != 0 else {
                self?.complete(
                    error: ProviderFailure.network(
                        "The Codex app-server closed before returning usage limits."
                    )
                )
                return
            }
            self?.complete(
                error: ProviderFailure.network(
                    "The Codex app-server exited with status \(terminatedProcess.terminationStatus)."
                )
            )
        }

        do {
            try process.run()
            try send(
                #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"usage-beacon","title":"UsageBeacon","version":"1"},"capabilities":{"experimentalApi":true}}}"#
            )
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw ProviderFailure.misconfigured(
                "UsageBeacon could not start Codex at \(executablePath): \(error.localizedDescription)"
            )
        }

        if completion.wait(timeout: .now() + timeout) == .timedOut {
            complete(error: ProviderFailure.network("Codex timed out while reading usage limits."))
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }

        lock.lock()
        defer { lock.unlock() }
        if let responseData {
            return responseData
        }
        throw responseError ?? ProviderFailure.network("Codex did not return usage limits.")
    }

    private func consume(_ data: Data) {
        guard data.isEmpty == false else {
            return
        }

        lock.lock()
        readBuffer.append(data)
        var lines: [Data] = []
        while let newline = readBuffer.firstIndex(of: 0x0A) {
            lines.append(readBuffer[..<newline])
            readBuffer.removeSubrange(...newline)
        }
        lock.unlock()

        for line in lines where line.isEmpty == false {
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let dictionary = object as? [String: Any],
            let identifier = dictionary["id"] as? NSNumber
        else {
            return
        }

        switch identifier.intValue {
        case 1:
            lock.lock()
            let shouldRequest = didRequestRateLimits == false
            didRequestRateLimits = true
            lock.unlock()
            guard shouldRequest else {
                return
            }

            do {
                try send(#"{"method":"initialized"}"#)
                try send(#"{"id":2,"method":"account/rateLimits/read"}"#)
            } catch {
                complete(error: ProviderFailure.network("UsageBeacon lost its connection to the Codex app-server."))
            }
        case 2:
            complete(response: line)
        default:
            break
        }
    }

    private func send(_ message: String) throws {
        guard let data = (message + "\n").data(using: .utf8), let inputHandle else {
            throw ProviderFailure.network("The Codex app-server input stream is unavailable.")
        }
        try inputHandle.write(contentsOf: data)
    }

    private func complete(response: Data? = nil, error: Error? = nil) {
        lock.lock()
        guard isComplete == false else {
            lock.unlock()
            return
        }
        isComplete = true
        responseData = response
        responseError = error
        lock.unlock()
        completion.signal()
    }
}
