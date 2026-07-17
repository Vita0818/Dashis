import Foundation

enum ProviderHTTPError: LocalizedError, Equatable {
  case blockedEndpoint
  case transport
  case invalidResponse
  case httpStatus(Int)
  case emptyResponse
  case invalidJSON
  case responseTooLarge

  var errorDescription: String? {
    switch self {
    case .blockedEndpoint:
      "Endpoint policy rejected the request."
    case .transport:
      "The provider could not be reached."
    case .invalidResponse:
      "The provider returned an invalid response."
    case .httpStatus(let code):
      code == 429 ? "The provider rate-limited this check." : "The provider returned HTTP \(code)."
    case .emptyResponse:
      "The provider returned an empty response."
    case .invalidJSON:
      "The provider returned an unsupported response."
    case .responseTooLarge:
      "The provider response exceeded the safety limit."
    }
  }
}

final class ProviderHTTPClient: @unchecked Sendable {
  private let redirectDelegate: ProviderRedirectDelegate
  private let session: URLSession
  private let maximumRetries: Int
  private let maximumResponseBytes: Int

  init(
    configuration: URLSessionConfiguration? = nil,
    maximumRetries: Int = 1,
    maximumResponseBytes: Int = 8 * 1_024 * 1_024
  ) {
    let config = configuration ?? Self.ephemeralConfiguration()
    redirectDelegate = ProviderRedirectDelegate()
    session = URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    self.maximumRetries = max(0, maximumRetries)
    self.maximumResponseBytes = max(1_024, maximumResponseBytes)
  }

  deinit {
    session.invalidateAndCancel()
  }

  func json(for request: URLRequest, operation: String) async throws -> Any {
    let data = try await data(for: request, operation: operation)
    guard let object = try? JSONSerialization.jsonObject(with: data) else {
      throw ProviderHTTPError.invalidJSON
    }
    return object
  }

  func data(for request: URLRequest, operation: String) async throws -> Data {
    guard ProviderEndpointPolicy.allows(request) else {
      throw ProviderHTTPError.blockedEndpoint
    }

    var attempt = 0
    let isIdempotent = ["GET", "HEAD"].contains(request.httpMethod?.uppercased() ?? "")
    while true {
      do {
        var safeRequest = request
        safeRequest.cachePolicy = .reloadIgnoringLocalCacheData
        safeRequest.timeoutInterval = 20
        safeRequest.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        safeRequest.setValue(UUID().uuidString, forHTTPHeaderField: "X-Dashis-Request-ID")

        let (bytes, response) = try await session.bytes(for: safeRequest)
        guard let http = response as? HTTPURLResponse else {
          throw ProviderHTTPError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
          let error = ProviderHTTPError.httpStatus(http.statusCode)
          if isIdempotent,
             attempt < maximumRetries,
             Self.retryableStatusCodes.contains(http.statusCode) {
            attempt += 1
            try await Self.backoff(attempt: attempt)
            continue
          }
          throw error
        }
        if http.expectedContentLength > Int64(maximumResponseBytes) {
          throw ProviderHTTPError.responseTooLarge
        }
        var data = Data()
        if http.expectedContentLength > 0 {
          data.reserveCapacity(min(maximumResponseBytes, Int(http.expectedContentLength)))
        }
        for try await byte in bytes {
          guard data.count < maximumResponseBytes else {
            throw ProviderHTTPError.responseTooLarge
          }
          data.append(byte)
        }
        guard !data.isEmpty else {
          throw ProviderHTTPError.emptyResponse
        }
        return data
      } catch let error as ProviderHTTPError {
        throw error
      } catch let error as URLError {
        if isIdempotent,
           attempt < maximumRetries,
           Self.retryableURLCodes.contains(error.code) {
          attempt += 1
          try await Self.backoff(attempt: attempt)
          continue
        }
        throw ProviderHTTPError.transport
      } catch {
        throw ProviderHTTPError.transport
      }
    }
  }

  private static func ephemeralConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.httpMaximumConnectionsPerHost = 4
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    return configuration
  }

  private static let retryableStatusCodes = Set([429, 502, 503, 504])
  private static let retryableURLCodes: Set<URLError.Code> = [
    .timedOut,
    .cannotConnectToHost,
    .networkConnectionLost,
    .notConnectedToInternet
  ]

  private static func backoff(attempt: Int) async throws {
    let milliseconds = UInt64(min(1_000, 200 * attempt))
    try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
  }
}

private final class ProviderRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
