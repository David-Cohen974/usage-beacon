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
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw ProviderFailure.network("HTTP \(httpResponse.statusCode): \(body)")
        }
        return (data, httpResponse)
    }
}
