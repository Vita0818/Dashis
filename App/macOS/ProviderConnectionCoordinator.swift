import Foundation

final class ProviderConnectionCoordinator: @unchecked Sendable {
  private let httpClient: ProviderHTTPClient
  private let loopback: LoopbackOAuthCoordinator
  private let cancellationLock = NSLock()
  private var activeCancellation: (id: UUID, cancel: @Sendable () -> Void)?

  init(
    httpClient: ProviderHTTPClient = ProviderHTTPClient(),
    loopback: LoopbackOAuthCoordinator = LoopbackOAuthCoordinator()
  ) {
    self.httpClient = httpClient
    self.loopback = loopback
  }

  func cancelActiveConnections() {
    cancellationLock.lock()
    let cancellation = activeCancellation
    activeCancellation = nil
    cancellationLock.unlock()
    cancellation?.cancel()
    loopback.cancelActiveAuthorization()
  }

  func connectOpenRouter() async throws -> String {
    try await runCancellable { [self] in
      try await performOpenRouterConnection()
    }
  }

  private func performOpenRouterConnection() async throws -> String {
    let pkce = try ProviderPKCE.generate()
    let callback = try await loopback.authorize(
      expectedState: nil,
      callbackPathPrefix: "/dashis/openrouter/oauth"
    ) { redirectURI in
      var components = URLComponents(string: "https://openrouter.ai/auth")
      components?.queryItems = [
        URLQueryItem(name: "callback_url", value: redirectURI.absoluteString),
        URLQueryItem(name: "code_challenge", value: pkce.challenge),
        URLQueryItem(name: "code_challenge_method", value: "S256")
      ]
      return components?.url
    }
    try Task.checkCancellation()
    return try await OpenRouterUsageClient(httpClient: httpClient)
      .exchangeAuthorizationCode(code: callback.code, codeVerifier: pkce.verifier)
  }

  func connectGoogle(clientID: String) async throws -> GoogleSessionAccessToken {
    try await runCancellable { [self] in
      try await performGoogleConnection(clientID: clientID)
    }
  }

  private func performGoogleConnection(clientID: String) async throws -> GoogleSessionAccessToken {
    let flowBox = ProviderLockedBox<GoogleDesktopOAuthFlow>()
    defer { flowBox.clear() }

    let callback = try await loopback.authorize(
      expectedState: nil,
      callbackPathPrefix: "/dashis/google/oauth"
    ) { redirectURI in
      guard let flow = try? GoogleDesktopOAuth.makeAuthorizationFlow(
        clientID: clientID,
        redirectURI: redirectURI
      ) else {
        return nil
      }
      flowBox.set(flow)
      return flow.authorizationURL
    }
    try Task.checkCancellation()
    guard let flow = flowBox.value else {
      throw GoogleDesktopOAuthError.invalidAuthorizationURL
    }
    let code = try GoogleDesktopOAuth.authorizationCode(
      from: callback.callbackURL,
      flow: flow
    )
    let request = try GoogleDesktopOAuth.tokenExchangeRequest(
      authorizationCode: code,
      clientID: clientID,
      flow: flow
    )
    try Task.checkCancellation()
    let data = try await httpClient.data(for: request, operation: "google.oauth.token")
    return try GoogleDesktopOAuth.sessionAccessToken(from: data)
  }

  private func runCancellable<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let id = UUID()
    let token = ProviderConnectionCancellationToken<Value>()
    let previous = replaceActiveCancellation(id: id, cancel: { [loopback] in
      token.cancel()
      loopback.cancelActiveAuthorization()
    })
    previous?.cancel()
    defer { clearActiveCancellation(id: id) }
    return try await withTaskCancellationHandler {
      let task = Task { try await operation() }
      token.install(task)
      return try await task.value
    } onCancel: { [loopback] in
      token.cancel()
      loopback.cancelActiveAuthorization()
    }
  }

  private func replaceActiveCancellation(
    id: UUID,
    cancel: @escaping @Sendable () -> Void
  ) -> (id: UUID, cancel: @Sendable () -> Void)? {
    cancellationLock.lock()
    defer { cancellationLock.unlock() }
    let previous = activeCancellation
    activeCancellation = (id, cancel)
    return previous
  }

  private func clearActiveCancellation(id: UUID) {
    cancellationLock.lock()
    defer { cancellationLock.unlock() }
    if activeCancellation?.id == id { activeCancellation = nil }
  }
}

private final class ProviderConnectionCancellationToken<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var task: Task<Value, Error>?
  private var isCancelled = false

  func install(_ task: Task<Value, Error>) {
    lock.lock()
    self.task = task
    let shouldCancel = isCancelled
    lock.unlock()
    if shouldCancel { task.cancel() }
  }

  func cancel() {
    lock.lock()
    isCancelled = true
    let task = task
    lock.unlock()
    task?.cancel()
  }
}

private final class ProviderLockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Value?

  var value: Value? {
    lock.lock()
    defer { lock.unlock() }
    return storedValue
  }

  func set(_ value: Value) {
    lock.lock()
    storedValue = value
    lock.unlock()
  }

  func clear() {
    lock.lock()
    storedValue = nil
    lock.unlock()
  }
}
