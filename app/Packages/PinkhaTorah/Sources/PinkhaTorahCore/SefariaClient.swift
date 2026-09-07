import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
}

public protocol TorahHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTorahTransport: TorahHTTPTransport {
    private let session: URLSession
    public init(timeout: TimeInterval = 12) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: configuration)
    }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TorahError.malformedResponse }
            return (data, http)
        } catch {
            if isCancellation(error) { throw CancellationError() }
            throw error
        }
    }
}

public struct SefariaClient: Sendable {
    private let transport: any TorahHTTPTransport
    private let baseURL: URL
    public init(transport: any TorahHTTPTransport = URLSessionTorahTransport(), baseURL: URL = URL(string: "https://www.sefaria.org")!) {
        self.transport = transport; self.baseURL = baseURL
    }

    public func get(pathSegments: [String], query: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        var url = baseURL
        for segment in pathSegments { url.append(path: segment) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw TorahError.malformedResponse }
        components.queryItems = query.isEmpty ? nil : query
        guard let requestURL = components.url else { throw TorahError.malformedResponse }
        var request = URLRequest(url: requestURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do { return try await transport.data(for: request) }
        catch {
            if isCancellation(error) { throw CancellationError() }
            if let error = error as? TorahError { throw error }
            throw TorahError.network(error.localizedDescription)
        }
    }
}
