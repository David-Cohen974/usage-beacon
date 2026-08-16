import AppKit
import Foundation
import WebKit

struct CursorDashboardPageSnapshot: Codable, Equatable {
    var title: String
    var urlString: String
    var bodyText: String
    var anchorHrefs: [String]
    var resourceURLs: [String]
    var nextDataSample: String?

    var url: URL? {
        URL(string: urlString)
    }

    var isCursorURL: Bool {
        guard let host = url?.host?.lowercased() else {
            return false
        }
        return host.contains("cursor.com") || host.contains("cursor.sh")
    }

    var looksUnauthenticated: Bool {
        let loweredTitle = title.lowercased()
        let loweredBody = bodyText.lowercased()
        let loweredURL = urlString.lowercased()
        return loweredURL.contains("authenticator.cursor.sh")
            || loweredTitle.contains("sign in")
            || loweredBody.contains("continue with email")
    }

    var looksUsageLike: Bool {
        if !isCursorURL {
            return bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        let loweredBody = bodyText.lowercased()
        return loweredBody.contains("usage")
            && (
                loweredBody.contains("resets")
                    || loweredBody.contains("current usage")
                    || loweredBody.contains("on-demand usage")
                    || loweredBody.contains("monthly spending limit")
                    || loweredBody.contains("current month")
                    || loweredBody.contains("rate limit")
            )
    }
}

enum CursorDashboardSessionState: Equatable {
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
final class CursorDashboardSessionController: NSObject, NSWindowDelegate {
    static let shared = CursorDashboardSessionController()

    var onStateChange: ((CursorDashboardSessionState) -> Void)?

    private(set) var state: CursorDashboardSessionState = .unknown {
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
        let titleLabel = NSTextField(wrappingLabelWithString: "Sign in to Cursor and leave this window on your usage page. UsageBeacon will reuse this session.")
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
        window.title = "Connect Cursor Personal"
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
        let cursorRecords = records.filter {
            let displayName = $0.displayName.lowercased()
            return displayName.contains("cursor")
        }

        if cursorRecords.isEmpty == false {
            await removeData(ofTypes: dataTypes, for: cursorRecords)
        }

        state = .disconnected
    }

    func refreshSessionState(pageURL: String) async -> CursorDashboardSessionState {
        do {
            _ = try await loadUsagePage(pageURL: pageURL)
            state = .connected
        } catch {
            if isSignInError(error) {
                state = .disconnected
            } else {
                state = .unknown
            }
        }
        return state
    }

    func loadUsagePage(pageURL: String) async throws -> CursorDashboardPageSnapshot {
        guard let url = URL(string: pageURL) else {
            throw ProviderFailure.misconfigured("Cursor usage page URL is invalid.")
        }
        let loader = CursorDashboardPageLoader(configuration: makeConfiguration())
        let snapshot = try await loader.load(url: url)
        if snapshot.isCursorURL && snapshot.looksUnauthenticated {
            throw ProviderFailure.misconfigured("Cursor is not signed in. Click Connect and finish the sign-in flow first.")
        }
        return snapshot
    }

    func authenticatedGET(urlString: String) async throws -> (Data, HTTPURLResponse) {
        try await authenticatedRequest(
            urlString: urlString,
            method: "GET",
            jsonData: nil
        )
    }

    func authenticatedPOST(
        urlString: String,
        jsonData: Data
    ) async throws -> (Data, HTTPURLResponse) {
        try await authenticatedRequest(
            urlString: urlString,
            method: "POST",
            jsonData: jsonData
        )
    }

    private func authenticatedRequest(
        urlString: String,
        method: String,
        jsonData: Data?
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else {
            throw ProviderFailure.misconfigured("Cursor endpoint URL is invalid.")
        }

        let cookies = await cookies(for: url)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let jsonData {
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/dashboard/usage", forHTTPHeaderField: "Referer")
        }
        for (header, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderFailure.network("Cursor endpoint response was invalid.")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            state = .disconnected
            throw ProviderFailure.misconfigured("Cursor personal session expired. Click Connect and sign in again.")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderFailure.network("Cursor endpoint failed with HTTP \(httpResponse.statusCode): \(body)")
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
                if let snapshot = try? await webView.pageSnapshot() {
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

    private func isSignInError(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("sign in")
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
private final class CursorDashboardPageLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(url: URL) async throws -> CursorDashboardPageSnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }

        var latestSnapshot = CursorDashboardPageSnapshot(
            title: "",
            urlString: url.absoluteString,
            bodyText: "",
            anchorHrefs: [],
            resourceURLs: [],
            nextDataSample: nil
        )
        let timeoutAt = Date().addingTimeInterval(15)

        while Date() < timeoutAt {
            let snapshot = try await webView.pageSnapshot()
            latestSnapshot = snapshot

            if snapshot.isCursorURL && snapshot.looksUnauthenticated {
                return snapshot
            }

            if snapshot.looksUsageLike {
                return snapshot
            }

            try await Task.sleep(for: .milliseconds(400))
        }

        if latestSnapshot.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return latestSnapshot
        }

        throw ProviderFailure.network("Cursor usage page did not finish loading.")
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
    func pageSnapshot() async throws -> CursorDashboardPageSnapshot {
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
            return nextData.textContent.slice(0, 4000);
          })()
        }))()
        """

        let rawValue = try await evaluateJavaScriptString(script)

        return try JSONDecoder().decode(CursorDashboardPageSnapshot.self, from: Data(rawValue.utf8))
    }

    func evaluateJavaScriptString(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let stringValue = value as? String {
                    continuation.resume(returning: stringValue)
                } else {
                    continuation.resume(throwing: ProviderFailure.parsing("Cursor page snapshot was not readable."))
                }
            }
        }
    }
}
