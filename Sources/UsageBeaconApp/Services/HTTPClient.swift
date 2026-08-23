import Foundation

protocol HTTPClientProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClientProtocol, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderFailure.network("The server returned a non-HTTP response.")
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            let statusDescription = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw ProviderFailure.httpStatus(
                code: httpResponse.statusCode,
                message: "HTTP \(httpResponse.statusCode) (\(statusDescription)).",
                retryAfterSeconds: Self.retryAfterSeconds(from: httpResponse)
            )
        }
        return (data, httpResponse)
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else {
            return nil
        }
        return max(0, date.timeIntervalSinceNow)
    }
}
