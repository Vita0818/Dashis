import CryptoKit
import DashisCollectorContract
import Foundation

protocol CollectorWorkerTransport: Sendable {
  func handshake(budgetMilliseconds: Int) async throws -> CollectorWorkerHandshake
  func catalog(budgetMilliseconds: Int) async throws -> [CollectorProvider]
  func collect(
    _ request: CollectorRequest,
    authorization: CollectorRouteAuthorization,
    configurationEnvironment: [String: String],
    budgetMilliseconds: Int
  ) async throws -> CollectorWireReply
}

enum CollectorWorkerClientError: Error, Equatable, LocalizedError {
  case transport(String)
  case invalidReply(String)
  case deadlineExceeded
  case cancelled

  var errorDescription: String? {
    switch self {
    case let .transport(message):
      "Collector worker transport failed: \(message)"
    case let .invalidReply(message):
      "Collector worker returned an invalid reply: \(message)"
    case .deadlineExceeded:
      "Collector worker exceeded its operation deadline."
    case .cancelled:
      "Collector worker operation was cancelled."
    }
  }
}

actor CollectorWorkerClient: CollectorWorkerTransport {
  private let serviceName: String

  init(serviceName: String = DashisCollectorXPC.serviceName) {
    self.serviceName = serviceName
  }

  func handshake(
    budgetMilliseconds: Int = 5_000
  ) async throws -> CollectorWorkerHandshake {
    let reply = try await send(.handshake(budgetMilliseconds: budgetMilliseconds))
    guard reply.status == .success, let handshake = reply.handshake else {
      throw CollectorWorkerClientError.invalidReply(
        reply.failure?.code ?? "missing_handshake")
    }
    guard handshake.wireVersion == CollectorWireRequest.currentWireVersion,
          handshake.outcomeSchemaVersion == CollectorOutcome.currentSchemaVersion,
          handshake.workerBundleIdentifier == DashisCollectorXPC.serviceName,
          !handshake.workerBundleVersion.isEmpty,
          handshake.maximumRequestBytes == CollectorWireLimits.maximumRequestBytes,
          handshake.maximumResponseBytes == CollectorWireLimits.maximumResponseBytes,
          handshake.upstreamPin == CollectorWireIdentity.codexBarUpstreamPin,
          handshake.rolloutCatalogRevision == CollectorRolloutCatalog.revision,
          handshake.stagedProviderCount
            == CollectorRolloutCatalog.selectedProviderIDs.count,
          handshake.stagedStrategyCount
            == CollectorRolloutCatalog.strategies.count,
          handshake.stagedBindingCount
            == CollectorRolloutCatalog.bindings.count,
          handshake.liveRouteCount == CollectorLiveRouteCatalog.routes.count,
          handshake.liveCatalogRevision == CollectorLiveRouteCatalog.revision,
          handshake.liveManifestSetDigest
            == Self.sha256(CollectorLiveRouteCatalog.manifestSetMaterial)
    else {
      throw CollectorWorkerClientError.invalidReply("incompatible_handshake")
    }
    return handshake
  }

  func catalog(
    budgetMilliseconds: Int = 5_000
  ) async throws -> [CollectorProvider] {
    let reply = try await send(.catalog(budgetMilliseconds: budgetMilliseconds))
    guard reply.status == .success, let catalog = reply.catalog else {
      throw CollectorWorkerClientError.invalidReply(
        reply.failure?.code ?? "missing_catalog")
    }
    return catalog
  }

  func collect(
    _ request: CollectorRequest,
    authorization: CollectorRouteAuthorization,
    configurationEnvironment: [String: String],
    budgetMilliseconds: Int
  ) async throws -> CollectorWireReply {
    let wireRequest = CollectorWireRequest.collect(
      request,
      authorization: authorization,
      budgetMilliseconds: budgetMilliseconds)
    let broker = CollectorLiveRouteCatalog.route(id: authorization.routeID)
      .flatMap { route -> CollectorHostBrokerServer? in
        guard route.provider == request.provider else {
          return nil
        }
        return CollectorHostBrokerServer(
          requestID: wireRequest.requestID,
          authorization: authorization,
          route: route,
          environment: Self.leasedEnvironment(
            explicit: configurationEnvironment,
            route: route))
      }
    return try await send(wireRequest, broker: broker)
  }

  private func send(
    _ request: CollectorWireRequest,
    broker: CollectorHostBrokerServer? = nil
  ) async throws -> CollectorWireReply {
    let requestData = try CollectorWireCodec.encodeRequest(request)
    let replyBox = CollectorWireReplyBox()
    let operation = CollectorXPCOperationState(
      requestID: request.requestID,
      replyBox: replyBox)

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        replyBox.install(continuation)

        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(
          with: DashisCollectorXPCProtocol.self)
        if let broker {
          connection.exportedInterface = NSXPCInterface(
            with: DashisCollectorHostBrokerXPCProtocol.self)
          connection.exportedObject = broker
        }
        connection.interruptionHandler = {
          operation.complete()
          replyBox.resolve(.failure(
            CollectorWorkerClientError.transport("connection_interrupted")))
        }
        connection.invalidationHandler = {
          operation.complete()
          replyBox.resolve(.failure(
            CollectorWorkerClientError.transport("connection_invalidated")))
        }
        guard operation.install(connection, broker: broker) else {
          return
        }
        connection.resume()
        guard operation.beginSend() else {
          connection.invalidate()
          return
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
          operation.complete()
          replyBox.resolve(.failure(
            CollectorWorkerClientError.transport(Self.sanitize(error))))
          connection.invalidate()
        }) as? DashisCollectorXPCProtocol else {
          replyBox.resolve(.failure(
            CollectorWorkerClientError.transport("remote_proxy_unavailable")))
          connection.invalidate()
          return
        }

        proxy.send(requestData) { responseData, responseError in
          defer {
            operation.complete()
            connection.invalidate()
          }
          if let responseError {
            replyBox.resolve(.failure(
              CollectorWorkerClientError.transport(Self.sanitize(responseError))))
            return
          }
          guard let responseData else {
            replyBox.resolve(.failure(
              CollectorWorkerClientError.invalidReply("missing_response_data")))
            return
          }
          do {
            let reply = try CollectorWireCodec.decodeReply(responseData)
            guard reply.requestID == request.requestID else {
              throw CollectorWorkerClientError.invalidReply("request_id_mismatch")
            }
            guard Self.reply(reply, matches: request.operation) else {
              throw CollectorWorkerClientError.invalidReply(
                "operation_payload_mismatch")
            }
            replyBox.resolve(.success(reply))
          } catch let error as CollectorWorkerClientError {
            replyBox.resolve(.failure(error))
          } catch {
            replyBox.resolve(.failure(
              CollectorWorkerClientError.invalidReply("wire_decode_failed")))
          }
        }

        operation.scheduleDeadline(milliseconds: request.budgetMilliseconds)
      }
    } onCancel: {
      operation.cancel()
    }
  }

  nonisolated private static func sanitize(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(nsError.domain)#\(nsError.code)"
  }

  nonisolated private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  /// Resolves matching ambient provider variables in the App process, then
  /// passes them through the same one-use broker as explicit UI values.
  /// The Worker never inherits provider credentials directly.
  nonisolated private static func leasedEnvironment(
    explicit: [String: String],
    route: CollectorLiveRouteDefinition
  ) -> [String: String] {
    let allowed = Set(route.allowedConfigurationKeys)
    var environment = ProcessInfo.processInfo.environment.filter {
      allowed.contains($0.key) && !$0.value.isEmpty
    }
    for (key, value) in explicit
    where allowed.contains(key) && !value.isEmpty {
      environment[key] = value
    }
    return environment
  }

  nonisolated private static func reply(
    _ reply: CollectorWireReply,
    matches operation: CollectorWireOperation
  ) -> Bool {
    switch operation {
    case .handshake:
      reply.handshake != nil
    case .catalog:
      reply.catalog != nil
    case .collect:
      reply.outcome != nil || reply.failure != nil
    case .cancel:
      reply.failure != nil
    }
  }
}

private final class CollectorWireReplyBox: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation:
    CheckedContinuation<CollectorWireReply, Error>?
  private var pendingResult: Result<CollectorWireReply, Error>?
  private var completed = false

  func install(
    _ continuation: CheckedContinuation<CollectorWireReply, Error>
  ) {
    let result: Result<CollectorWireReply, Error>?
    lock.lock()
    if completed {
      result = pendingResult
      pendingResult = nil
    } else {
      self.continuation = continuation
      result = nil
    }
    lock.unlock()
    if let result {
      continuation.resume(with: result)
    }
  }

  func resolve(_ result: Result<CollectorWireReply, Error>) {
    let continuation: CheckedContinuation<CollectorWireReply, Error>?
    lock.lock()
    guard !completed else {
      lock.unlock()
      return
    }
    completed = true
    continuation = self.continuation
    self.continuation = nil
    if continuation == nil {
      pendingResult = result
    }
    lock.unlock()
    continuation?.resume(with: result)
  }
}

private final class CollectorXPCOperationState: @unchecked Sendable {
  private let lock = NSLock()
  private let requestID: UUID
  private let replyBox: CollectorWireReplyBox
  private var connection: NSXPCConnection?
  private var broker: AnyObject?
  private var finished = false

  init(requestID: UUID, replyBox: CollectorWireReplyBox) {
    self.requestID = requestID
    self.replyBox = replyBox
  }

  func install(_ connection: NSXPCConnection, broker: AnyObject?) -> Bool {
    lock.lock()
    if finished {
      lock.unlock()
      connection.invalidate()
      return false
    }
    self.connection = connection
    self.broker = broker
    lock.unlock()
    return true
  }

  func beginSend() -> Bool {
    lock.lock()
    let canSend = !finished
    lock.unlock()
    return canSend
  }

  func scheduleDeadline(milliseconds: Int) {
    DispatchQueue.global(qos: .utility).asyncAfter(
      deadline: .now() + .milliseconds(milliseconds)
    ) { [weak self] in
      self?.finish(
        error: CollectorWorkerClientError.deadlineExceeded,
        sendCancellation: true)
    }
  }

  func cancel() {
    finish(
      error: CollectorWorkerClientError.cancelled,
      sendCancellation: true)
  }

  func complete() {
    lock.lock()
    finished = true
    connection = nil
    broker = nil
    lock.unlock()
  }

  private func finish(error: Error, sendCancellation: Bool) {
    let connection: NSXPCConnection?
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    finished = true
    connection = self.connection
    broker = nil
    lock.unlock()

    replyBox.resolve(.failure(error))
    guard let connection else { return }
    if sendCancellation,
       let data = try? CollectorWireCodec.encodeRequest(.cancel(requestID)),
       let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in })
         as? DashisCollectorXPCProtocol
    {
      proxy.send(data) { _, _ in }
    }
    DispatchQueue.global(qos: .utility).asyncAfter(
      deadline: .now() + .milliseconds(250)
    ) {
      connection.invalidate()
    }
  }
}

final class CollectorHostBrokerServer: NSObject,
  DashisCollectorHostBrokerXPCProtocol, @unchecked Sendable
{
  private let lock = NSLock()
  private let requestID: UUID
  private let authorization: CollectorRouteAuthorization
  private let route: CollectorLiveRouteDefinition
  private var environment: [String: String]
  private var consumed = false

  init(
    requestID: UUID,
    authorization: CollectorRouteAuthorization,
    route: CollectorLiveRouteDefinition,
    environment: [String: String]
  ) {
    self.requestID = requestID
    self.authorization = authorization
    self.route = route
    let allowed = Set(route.allowedConfigurationKeys)
    self.environment = environment.filter {
      allowed.contains($0.key) && !$0.value.isEmpty
    }
  }

  func resolve(
    _ requestData: Data,
    withReply reply: @escaping (Data?, NSError?) -> Void
  ) {
    do {
      let request = try CollectorHostBrokerCodec.decodeRequest(requestData)
      let requestedKeys = Set(request.requestedKeys)
      let allowedKeys = Set(route.allowedConfigurationKeys)
      lock.lock()
      let valid = !consumed
        && request.requestID == requestID
        && request.leaseID == authorization.brokerLeaseID
        && request.routeID == route.id
        && request.provider == route.provider
        && requestedKeys == allowedKeys
      if valid {
        consumed = true
      }
      let values = valid
        ? environment.filter { requestedKeys.contains($0.key) }
        : [:]
      if valid {
        environment.removeAll(keepingCapacity: false)
      }
      lock.unlock()
      guard valid else {
        reply(nil, Self.error(code: 1, reason: "configuration_lease_denied"))
        return
      }
      reply(
        try CollectorHostBrokerCodec.encodeReply(
          CollectorHostBrokerReply(environment: values)),
        nil)
    } catch {
      reply(nil, Self.error(code: 2, reason: "invalid_broker_request"))
    }
  }

  private static func error(code: Int, reason: String) -> NSError {
    NSError(
      domain: DashisCollectorXPC.errorDomain,
      code: code,
      userInfo: [NSLocalizedDescriptionKey: reason])
  }
}
