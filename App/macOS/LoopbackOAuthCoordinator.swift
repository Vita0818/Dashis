import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct ProviderPKCE: Sendable {
  let verifier: String
  let challenge: String

  static func generate() throws -> ProviderPKCE {
    let verifier = try OAuthSecurity.randomURLSafeString(byteCount: 48)
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return ProviderPKCE(
      verifier: verifier,
      challenge: Data(digest).base64URLEncodedString()
    )
  }
}

struct LoopbackOAuthCallback: Sendable {
  let code: String
  let state: String?
  let redirectURI: URL
  let callbackURL: URL
}

enum LoopbackOAuthError: LocalizedError, Equatable {
  case listenerUnavailable
  case invalidAuthorizationURL
  case invalidCallback
  case stateMismatch
  case providerDenied
  case timedOut
  case cancelled

  var errorDescription: String? {
    switch self {
    case .listenerUnavailable:
      "Dashis could not start the local OAuth callback."
    case .invalidAuthorizationURL:
      "Dashis refused an invalid provider authorization URL."
    case .invalidCallback:
      "The provider returned an invalid OAuth callback."
    case .stateMismatch:
      "The OAuth callback state did not match this session."
    case .providerDenied:
      "The provider did not grant access."
    case .timedOut:
      "The OAuth authorization timed out."
    case .cancelled:
      "The OAuth authorization was cancelled."
    }
  }
}

enum OAuthSecurity {
  static func randomURLSafeString(byteCount: Int = 32) throws -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw LoopbackOAuthError.listenerUnavailable
    }
    return Data(bytes).base64URLEncodedString()
  }
}

final class LoopbackOAuthCoordinator: @unchecked Sendable {
  typealias AuthorizationURLBuilder = @Sendable (_ redirectURI: URL) -> URL?

  private let timeout: TimeInterval
  private let activeLock = NSLock()
  private var activeListener: NWListener?
  private var activeContinuation: AsyncThrowingStream<LoopbackOAuthCallback, Error>.Continuation?
  private var activeAuthorizationID: UUID?

  init(timeout: TimeInterval = 120) {
    self.timeout = timeout
  }

  func authorize(
    expectedState: String?,
    callbackPathPrefix: String = "/dashis/oauth",
    makeAuthorizationURL: @escaping AuthorizationURLBuilder
  ) async throws -> LoopbackOAuthCallback {
    let allowedPrefixes = ["/dashis/oauth", "/dashis/google/oauth", "/dashis/openrouter/oauth"]
    guard allowedPrefixes.contains(callbackPathPrefix) else {
      throw LoopbackOAuthError.invalidCallback
    }
    let callbackPath = "\(callbackPathPrefix)/\(try OAuthSecurity.randomURLSafeString(byteCount: 24))"
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener: NWListener
    do {
      listener = try NWListener(using: parameters)
    } catch {
      throw LoopbackOAuthError.listenerUnavailable
    }

    let stream: AsyncThrowingStream<LoopbackOAuthCallback, Error>
    let continuation: AsyncThrowingStream<LoopbackOAuthCallback, Error>.Continuation
    (stream, continuation) = AsyncThrowingStream.makeStream(of: LoopbackOAuthCallback.self)
    let redirectBox = OAuthRedirectBox()
    let expectedStateBox = OAuthExpectedStateBox(initialValue: expectedState)
    let connectionTracker = OAuthConnectionTracker(maximumConnections: 8)
    let authorizationID = UUID()
    let queue = DispatchQueue(label: "com.vitemis.dashis.oauth-loopback")
    beginAuthorization(id: authorizationID, listener: listener, continuation: continuation)

    listener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        guard self.isAuthorizationActive(id: authorizationID, listener: listener),
              let port = listener.port,
              let redirectURI = URL(string: "http://127.0.0.1:\(port.rawValue)\(callbackPath)"),
              let authorizationURL = makeAuthorizationURL(redirectURI),
              Self.isSafeAuthorizationURL(authorizationURL)
        else {
          continuation.finish(throwing: LoopbackOAuthError.invalidAuthorizationURL)
          return
        }
        redirectBox.set(redirectURI)
        let authorizationState = URLComponents(
          url: authorizationURL,
          resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == "state" })?.value
        if let expectedState, authorizationState != nil, authorizationState != expectedState {
          continuation.finish(throwing: LoopbackOAuthError.stateMismatch)
          return
        }
        expectedStateBox.setIfMissing(authorizationState)
        DispatchQueue.main.async { [weak self] in
          guard let self,
                self.isAuthorizationActive(id: authorizationID, listener: listener)
          else { return }
          if !NSWorkspace.shared.open(authorizationURL) {
            continuation.finish(throwing: LoopbackOAuthError.invalidAuthorizationURL)
          }
        }
      case .failed:
        continuation.finish(throwing: LoopbackOAuthError.listenerUnavailable)
      case .cancelled:
        break
      default:
        break
      }
    }

    listener.newConnectionHandler = { connection in
      guard connectionTracker.register(connection) else {
        connection.cancel()
        return
      }
      Self.handle(
        connection: connection,
        tracker: connectionTracker,
        callbackPath: callbackPath,
        expectedStateBox: expectedStateBox,
        redirectBox: redirectBox,
        continuation: continuation
      )
    }

    listener.start(queue: queue)
    defer {
      listener.cancel()
      connectionTracker.cancelAll()
      continuation.finish()
      endAuthorization(id: authorizationID, listener: listener)
    }

    return try await withThrowingTaskGroup(of: LoopbackOAuthCallback.self) { group in
      group.addTask {
        for try await callback in stream {
          return callback
        }
        throw LoopbackOAuthError.cancelled
      }
      group.addTask { [timeout] in
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw LoopbackOAuthError.timedOut
      }
      defer { group.cancelAll() }
      guard let result = try await group.next() else {
        throw LoopbackOAuthError.cancelled
      }
      return result
    }
  }

  func cancelActiveAuthorization() {
    activeLock.lock()
    let listener = activeListener
    let continuation = activeContinuation
    activeListener = nil
    activeContinuation = nil
    activeAuthorizationID = nil
    activeLock.unlock()

    listener?.cancel()
    continuation?.finish(throwing: LoopbackOAuthError.cancelled)
  }

  private func beginAuthorization(
    id: UUID,
    listener: NWListener,
    continuation: AsyncThrowingStream<LoopbackOAuthCallback, Error>.Continuation
  ) {
    activeLock.lock()
    let previousListener = activeListener
    let previousContinuation = activeContinuation
    activeListener = listener
    activeContinuation = continuation
    activeAuthorizationID = id
    activeLock.unlock()

    previousListener?.cancel()
    previousContinuation?.finish(throwing: LoopbackOAuthError.cancelled)
  }

  private func endAuthorization(id: UUID, listener: NWListener) {
    activeLock.lock()
    if activeAuthorizationID == id, activeListener === listener {
      activeListener = nil
      activeContinuation = nil
      activeAuthorizationID = nil
    }
    activeLock.unlock()
  }

  private func isAuthorizationActive(id: UUID, listener: NWListener) -> Bool {
    activeLock.lock()
    defer { activeLock.unlock() }
    return activeAuthorizationID == id && activeListener === listener
  }

  private static func handle(
    connection: NWConnection,
    tracker: OAuthConnectionTracker,
    callbackPath: String,
    expectedStateBox: OAuthExpectedStateBox,
    redirectBox: OAuthRedirectBox,
    continuation: AsyncThrowingStream<LoopbackOAuthCallback, Error>.Continuation
  ) {
    let queue = DispatchQueue(label: "com.vitemis.dashis.oauth-connection")
    connection.stateUpdateHandler = { state in
      switch state {
      case .cancelled, .failed:
        tracker.remove(connection)
      default:
        break
      }
    }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 10) {
      if tracker.remove(connection) {
        connection.cancel()
      }
    }
    receiveRequest(
      connection: connection,
      accumulated: Data(),
      callbackPath: callbackPath,
      expectedStateBox: expectedStateBox,
      redirectBox: redirectBox,
      continuation: continuation
    )
  }

  private static func receiveRequest(
    connection: NWConnection,
    accumulated: Data,
    callbackPath: String,
    expectedStateBox: OAuthExpectedStateBox,
    redirectBox: OAuthRedirectBox,
    continuation: AsyncThrowingStream<LoopbackOAuthCallback, Error>.Continuation
  ) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 2_048) { chunk, _, isComplete, error in
      guard error == nil else {
        connection.cancel()
        return
      }
      var data = accumulated
      if let chunk { data.append(chunk) }
      guard data.count <= 8_192 else {
        respond(connection: connection, status: "413 Payload Too Large", message: "The callback request was too large.")
        return
      }

      let headerTerminator = Data("\r\n\r\n".utf8)
      if data.range(of: headerTerminator) != nil || isComplete {
        processRequest(
          data,
          connection: connection,
          callbackPath: callbackPath,
          expectedStateBox: expectedStateBox,
          redirectBox: redirectBox,
          continuation: continuation
        )
      } else {
        receiveRequest(
          connection: connection,
          accumulated: data,
          callbackPath: callbackPath,
          expectedStateBox: expectedStateBox,
          redirectBox: redirectBox,
          continuation: continuation
        )
      }
    }
  }

  private static func processRequest(
    _ data: Data,
    connection: NWConnection,
    callbackPath: String,
    expectedStateBox: OAuthExpectedStateBox,
    redirectBox: OAuthRedirectBox,
    continuation: AsyncThrowingStream<LoopbackOAuthCallback, Error>.Continuation
  ) {
    guard let request = String(data: data, encoding: .utf8),
          let requestLine = request.split(separator: "\r\n", maxSplits: 1).first,
          requestLine.hasPrefix("GET "),
          let target = requestLine.split(separator: " ").dropFirst().first,
          let callbackURL = URL(string: String(target), relativeTo: URL(string: "http://127.0.0.1")),
          callbackURL.path == callbackPath,
          let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)
    else {
      respond(connection: connection, status: "404 Not Found", message: "This callback is not valid for Dashis.")
      return
    }

    let items = components.queryItems ?? []
    let values = Dictionary(grouping: items, by: \.name)
    guard values.values.allSatisfy({ $0.count == 1 }) else {
      respond(connection: connection, status: "400 Bad Request", message: "The callback was rejected.")
      continuation.finish(throwing: LoopbackOAuthError.invalidCallback)
      return
    }
    if values["error"] != nil {
      respond(connection: connection, status: "403 Forbidden", message: "Authorization was not granted. You can close this page.")
      continuation.finish(throwing: LoopbackOAuthError.providerDenied)
      return
    }

    let returnedState = values["state"]?.first?.value
    if let expectedState = expectedStateBox.value, returnedState != expectedState {
      respond(connection: connection, status: "403 Forbidden", message: "The authorization state did not match. You can close this page.")
      continuation.finish(throwing: LoopbackOAuthError.stateMismatch)
      return
    }
    guard let code = values["code"]?.first?.value,
          !code.isEmpty,
          code.count <= 4_096,
          let redirectURI = redirectBox.value
    else {
      respond(connection: connection, status: "400 Bad Request", message: "The provider did not return an authorization code.")
      continuation.finish(throwing: LoopbackOAuthError.invalidCallback)
      return
    }

    var returnedComponents = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false)
    returnedComponents?.queryItems = items
    guard let returnedCallbackURL = returnedComponents?.url else {
      respond(connection: connection, status: "400 Bad Request", message: "The provider callback could not be validated.")
      continuation.finish(throwing: LoopbackOAuthError.invalidCallback)
      return
    }

    respond(connection: connection, status: "200 OK", message: "Dashis is connected. You can close this page.")
    continuation.yield(LoopbackOAuthCallback(
      code: code,
      state: returnedState,
      redirectURI: redirectURI,
      callbackURL: returnedCallbackURL
    ))
    continuation.finish()
  }

  private static func respond(connection: NWConnection, status: String, message: String) {
    let escaped = message
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
    let body = "<!doctype html><meta charset=\"utf-8\"><title>Dashis</title><p>\(escaped)</p>"
    let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
      connection.cancel()
    })
  }

  private static func isSafeAuthorizationURL(_ url: URL) -> Bool {
    guard url.scheme == "https",
          url.port == nil || url.port == 443,
          url.user == nil,
          url.password == nil,
          url.fragment == nil
    else {
      return false
    }
    guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
      return false
    }
    let grouped = Dictionary(grouping: items, by: \.name)
    guard grouped.values.allSatisfy({ $0.count == 1 }) else { return false }

    switch (url.host?.lowercased(), url.path) {
    case ("openrouter.ai", "/auth"):
      guard Set(grouped.keys) == ["callback_url", "code_challenge", "code_challenge_method"],
            grouped["code_challenge_method"]?.first?.value == "S256",
            isSafeLoopbackRedirect(grouped["callback_url"]?.first?.value),
            isSafeChallenge(grouped["code_challenge"]?.first?.value)
      else { return false }
      return true
    case ("accounts.google.com", "/o/oauth2/v2/auth"):
      let required: Set<String> = [
        "client_id", "redirect_uri", "response_type", "scope",
        "code_challenge", "code_challenge_method", "state"
      ]
      let allowed = required.union(["access_type", "prompt"])
      guard required.isSubset(of: Set(grouped.keys)),
            Set(grouped.keys).isSubset(of: allowed),
            grouped["response_type"]?.first?.value == "code",
            grouped["code_challenge_method"]?.first?.value == "S256",
            grouped["scope"]?.first?.value == GoogleDesktopOAuth.cloudPlatformScope,
            isSafeLoopbackRedirect(grouped["redirect_uri"]?.first?.value),
            isSafeChallenge(grouped["code_challenge"]?.first?.value),
            let state = grouped["state"]?.first?.value,
            state.count >= 32,
            let clientID = grouped["client_id"]?.first?.value,
            clientID.count <= 512,
            clientID.hasSuffix(".apps.googleusercontent.com")
      else { return false }
      return true
    default:
      return false
    }
  }

  private static func isSafeChallenge(_ value: String?) -> Bool {
    guard let value else { return false }
    return value.count == 43
      && value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
  }

  private static func isSafeLoopbackRedirect(_ value: String?) -> Bool {
    guard let value,
          let url = URL(string: value),
          url.scheme == "http",
          url.host == "127.0.0.1",
          let port = url.port,
          (1...65_535).contains(port),
          ["/dashis/oauth/", "/dashis/google/oauth/", "/dashis/openrouter/oauth/"]
            .contains(where: url.path.hasPrefix),
          url.query == nil,
          url.fragment == nil,
          url.user == nil,
          url.password == nil
    else { return false }
    return true
  }
}

private extension Data {
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

private final class OAuthRedirectBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: URL?

  var value: URL? {
    lock.lock()
    defer { lock.unlock() }
    return storedValue
  }

  func set(_ value: URL) {
    lock.lock()
    storedValue = value
    lock.unlock()
  }
}

private final class OAuthExpectedStateBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: String?

  init(initialValue: String?) {
    storedValue = initialValue
  }

  var value: String? {
    lock.lock()
    defer { lock.unlock() }
    return storedValue
  }

  func setIfMissing(_ value: String?) {
    guard let value else { return }
    lock.lock()
    if storedValue == nil { storedValue = value }
    lock.unlock()
  }
}

private final class OAuthConnectionTracker: @unchecked Sendable {
  private let lock = NSLock()
  private let maximumConnections: Int
  private var connections: [ObjectIdentifier: NWConnection] = [:]

  init(maximumConnections: Int) {
    self.maximumConnections = maximumConnections
  }

  func register(_ connection: NWConnection) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard connections.count < maximumConnections else { return false }
    connections[ObjectIdentifier(connection)] = connection
    return true
  }

  @discardableResult
  func remove(_ connection: NWConnection) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return connections.removeValue(forKey: ObjectIdentifier(connection)) != nil
  }

  func cancelAll() {
    lock.lock()
    let active = Array(connections.values)
    connections.removeAll()
    lock.unlock()
    active.forEach { $0.cancel() }
  }
}
