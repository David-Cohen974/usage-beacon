import AppKit
import Foundation
import WebKit

struct ClaudeDashboardPageSnapshot: Codable, Equatable {
    var title: String
    var urlString: String
    var bodyText: String
    var anchorHrefs: [String]
    var resourceURLs: [String]
    var nextDataSample: String?

    var url: URL? {
        URL(string: urlString)
    }

    var isClaudeURL: Bool {
        guard let host = url?.host?.lowercased() else {
            return false
        }
        return host == "claude.ai" || host.hasSuffix(".claude.ai")
    }

    var looksUnauthenticated: Bool {
        guard isClaudeURL else {
            return false
        }

        let loweredTitle = title.lowercased()
        let loweredBody = bodyText.lowercased()
        let loweredURL = urlString.lowercased()
        return loweredURL.contains("claude.ai/login")
            || loweredTitle.contains("sign in")
            || loweredBody.contains("continue with google")
            || loweredBody.contains("continue with email")
    }

    var looksUsageLike: Bool {
        if !isClaudeURL {
            return bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        if resourceURLs.contains(where: { resourceURL in
            guard let components = URLComponents(string: resourceURL) else {
                return false
            }
            return components.host?.lowercased() == "claude.ai"
                && components.path.range(
                    of: #"^/api/organizations/[^/]+/usage$"#,
                    options: .regularExpression
                ) != nil
        }) {
            return true
        }

        let loweredBody = bodyText.lowercased()
        return loweredBody.contains("usage")
            && (
                loweredBody.contains("current session")
                    || loweredBody.contains("current week")
                    || loweredBody.contains("5-hour")
                    || loweredBody.contains("five-hour")
                    || loweredBody.contains("7-day")
                    || loweredBody.contains("seven-day")
                    || loweredBody.contains("month-to-date")
                    || loweredBody.contains("spend limit")
                    || loweredBody.contains("member analytics")
            )
    }
}

enum ClaudeDashboardSessionState: Equatable {
    case unknown
    case disconnected
    case connecting
    case connected

    var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .disconnected:
            return "Not signed in"
        case .connecting:
            return "Browser open for sign-in"
        case .connected:
            return "Connected"
        }
    }
}

@MainActor
final class ClaudeDashboardSessionController: NSObject, NSWindowDelegate {
    static let shared = ClaudeDashboardSessionController()

    var onStateChange: ((ClaudeDashboardSessionState) -> Void)?

    private(set) var state: ClaudeDashboardSessionState = .unknown {
        didSet {
            guard state != oldValue else {
                return
            }
            onStateChange?(state)
        }
    }

    private let dataStore = WKWebsiteDataStore.default()
    private var connectionWindow: NSWindow?
    private var connectionWebView: WKWebView?
    private var connectionMonitorTask: Task<Void, Never>?
    private var lastConnectionPageURL: String?

    func openConnectionWindow(pageURL: String) {
        guard let url = URL(string: pageURL) else {
            state = .unknown
            return
        }

        lastConnectionPageURL = pageURL
        state = .connecting
        connectionMonitorTask?.cancel()

        let webView = WKWebView(frame: .zero, configuration: makeConfiguration())
        webView.load(URLRequest(url: url))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1120, height: 800))
        let titleLabel = NSTextField(
            wrappingLabelWithString: "Sign in to Claude and leave this window on Settings → Usage. UsageBeacon will reuse only this local web session."
        )
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            webView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Connect Claude Personal"
        window.contentView = container
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        connectionWindow = window
        connectionWebView = webView
        beginConnectionMonitoring(webView: webView)
    }

    func disconnect() async {
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await fetchDataRecords(ofTypes: dataTypes)
        let claudeRecords = records.filter {
            let displayName = $0.displayName.lowercased()
            return displayName.contains("claude") || displayName.contains("anthropic")
        }

        if claudeRecords.isEmpty == false {
            await removeData(ofTypes: dataTypes, for: claudeRecords)
        }

        state = .disconnected
    }

    func refreshSessionState(pageURL: String) async -> ClaudeDashboardSessionState {
        do {
            _ = try await loadUsagePage(pageURL: pageURL)
            state = .connected
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("sign in") {
                state = .disconnected
            } else {
                state = .unknown
            }
        }
        return state
    }

    func loadUsagePage(pageURL: String) async throws -> ClaudeDashboardPageSnapshot {
        guard let url = URL(string: pageURL) else {
            throw ProviderFailure.misconfigured("Claude usage page URL is invalid.")
        }

        let loader = ClaudeDashboardPageLoader(configuration: makeConfiguration())
        let snapshot = try await loader.load(url: url)
        if snapshot.looksUnauthenticated {
            throw ProviderFailure.misconfigured("Claude is not signed in. Click Connect and finish the sign-in flow first.")
        }
        return snapshot
    }

    func authenticatedGET(urlString: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else {
            throw ProviderFailure.misconfigured("Claude endpoint URL is invalid.")
        }

        let cookies = await cookies(for: url)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai/new#settings/usage", forHTTPHeaderField: "Referer")
        for (header, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderFailure.network("Claude endpoint response was invalid.")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            state = .disconnected
            throw ProviderFailure.misconfigured("Claude personal session expired. Click Connect and sign in again.")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderFailure.network("Claude endpoint failed with HTTP \(httpResponse.statusCode): \(body)")
        }

        return (data, httpResponse)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow == connectionWindow else {
            return
        }

        connectionMonitorTask?.cancel()
        connectionMonitorTask = nil
        connectionWebView = nil
        connectionWindow = nil

        if state == .connecting, let pageURL = lastConnectionPageURL {
            Task { @MainActor [weak self] in
                _ = await self?.refreshSessionState(pageURL: pageURL)
            }
        }
    }

    private func beginConnectionMonitoring(webView: WKWebView) {
        connectionMonitorTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else {
                return
            }

            while Task.isCancelled == false {
                if let snapshot = try? await webView.claudePageSnapshot() {
                    if snapshot.looksUnauthenticated {
                        if self.state != .connecting {
                            self.state = .connecting
                        }
                    } else if snapshot.looksUsageLike {
                        self.state = .connected
                        break
                    }
                }

                try? await Task.sleep(for: .milliseconds(700))
            }

            self.connectionMonitorTask = nil
        }
    }

    private func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        return configuration
    }

    private func cookies(for url: URL) async -> [HTTPCookie] {
        let allCookies = await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        return allCookies.filter { cookie in
            guard let host = url.host?.lowercased() else {
                return false
            }
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return host == domain || host.hasSuffix(".\(domain)")
        }
    }

    private func fetchDataRecords(ofTypes types: Set<String>) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: types) { records in
                continuation.resume(returning: records)
            }
        }
    }

    private func removeData(ofTypes types: Set<String>, for records: [WKWebsiteDataRecord]) async {
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: types, for: records) {
                continuation.resume()
            }
        }
    }
}

@MainActor
private final class ClaudeDashboardPageLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(url: URL) async throws -> ClaudeDashboardPageSnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }

        var latestSnapshot = ClaudeDashboardPageSnapshot(
            title: "",
            urlString: url.absoluteString,
            bodyText: "",
            anchorHrefs: [],
            resourceURLs: [],
            nextDataSample: nil
        )
        let timeoutAt = Date().addingTimeInterval(15)

        while Date() < timeoutAt {
            let snapshot = try await webView.claudePageSnapshot()
            latestSnapshot = snapshot

            if snapshot.looksUnauthenticated || snapshot.looksUsageLike {
                return snapshot
            }

            try await Task.sleep(for: .milliseconds(400))
        }

        if latestSnapshot.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return latestSnapshot
        }

        throw ProviderFailure.network("Claude usage page did not finish loading.")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}

@MainActor
private extension WKWebView {
    func claudePageSnapshot() async throws -> ClaudeDashboardPageSnapshot {
        let script = """
        (() => JSON.stringify({
          title: document.title || "",
          urlString: location.href,
          bodyText: document.body ? document.body.innerText : "",
          anchorHrefs: Array.from(document.querySelectorAll('a[href]'))
            .map(anchor => anchor.href)
            .filter((href, index, all) => href && all.indexOf(href) === index)
            .slice(0, 200),
          resourceURLs: performance.getEntriesByType('resource')
            .map(entry => entry.name)
            .filter((href, index, all) => href && all.indexOf(href) === index)
            .slice(0, 200),
          nextDataSample: (() => {
            const nextData = document.querySelector('#__NEXT_DATA__');
            if (!nextData || !nextData.textContent) return null;
            return nextData.textContent.slice(0, 12000);
          })()
        }))()
        """

        let rawValue: String = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String, Error>) in
            evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let stringValue = value as? String {
                    continuation.resume(returning: stringValue)
                } else {
                    continuation.resume(
                        throwing: ProviderFailure.parsing("Claude page snapshot was not readable.")
                    )
                }
            }
        }

        return try JSONDecoder().decode(ClaudeDashboardPageSnapshot.self, from: Data(rawValue.utf8))
    }
}
