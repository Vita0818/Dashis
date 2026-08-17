import CodexBarCollector
import CryptoKit
import DashisCollectorContract
import Darwin
import Foundation

struct CollectorWorkerHostBroker: Sendable {
  let resolve:
    @Sendable (
      _ requestID: UUID,
      _ authorization: CollectorRouteAuthorization,
      _ route: CollectorLiveRouteDefinition
    ) async throws -> [String: String]
}

actor CollectorWorkerCoordinator {
  static let shared = CollectorWorkerCoordinator()

  private struct ActiveCollection {
    let requestID: UUID
    let task: Task<CollectorOutcome, Never>
    let deadlineTask: Task<Void, Never>
    let hardTerminationTask: Task<Void, Never>
    let cleanupController: CollectorWorkerCleanupController
  }

  private struct PendingCollection {
    let requestID: UUID
    let hardTerminationTask: Task<Void, Never>
    let cleanupController: CollectorWorkerCleanupController
    var cancelled: Bool
  }

  private let catalogCollector = CodexBarCollector()
  private let routeRegistry = CollectorWorkerRouteRegistry.production
  private var pendingCollection: PendingCollection?
  private var activeCollection: ActiveCollection?
  private var recentRequestIDs: [UUID] = []
  private var recentRequestIDSet = Set<UUID>()

  func handle(
    _ request: CollectorWireRequest,
    broker: CollectorWorkerHostBroker?
  ) async -> CollectorWireReply {
    guard register(request.requestID) else {
      return failure(
        requestID: request.requestID,
        status: .invalidRequest,
        code: "duplicate_request_id",
        message: "The worker rejected a duplicate request identifier.")
    }

    switch request.operation {
    case .handshake:
      return CollectorWireReply(
        requestID: request.requestID,
        status: .success,
        handshake: CollectorWorkerHandshake(
          wireVersion: CollectorWireRequest.currentWireVersion,
          outcomeSchemaVersion: CollectorOutcome.currentSchemaVersion,
          workerBundleIdentifier: Bundle.main.bundleIdentifier
            ?? DashisCollectorXPC.serviceName,
          workerBundleVersion: Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
          maximumRequestBytes: CollectorWireLimits.maximumRequestBytes,
          maximumResponseBytes: CollectorWireLimits.maximumResponseBytes,
          upstreamPin: CollectorWireIdentity.codexBarUpstreamPin,
          rolloutCatalogRevision: CollectorRolloutCatalog.revision,
          stagedProviderCount: CollectorRolloutCatalog.selectedProviderIDs.count,
          stagedStrategyCount: CollectorRolloutCatalog.strategies.count,
          stagedBindingCount: CollectorRolloutCatalog.bindings.count,
          liveRouteCount: routeRegistry.liveRouteCount,
          liveCatalogRevision: CollectorLiveRouteCatalog.revision,
          liveManifestSetDigest: Self.sha256(
            CollectorLiveRouteCatalog.manifestSetMaterial)))
    case .catalog:
      let providers = await catalogCollector.catalog()
      return CollectorWireReply(
        requestID: request.requestID,
        status: .success,
        catalog: providers)
    case .collect:
      guard let collectorRequest = request.collectorRequest else {
        return failure(
          requestID: request.requestID,
          status: .invalidRequest,
          code: "missing_collector_request",
          message: "The collection envelope did not contain a request.")
      }
      guard let authorization = request.authorization,
            let route = routeRegistry.resolve(
              collectorRequest,
              authorization: authorization)
      else {
        return failure(
          requestID: request.requestID,
          status: .denied,
          code: "route_authorization_denied",
          message: "The worker rejected an unknown or mismatched route manifest.")
      }
      guard !route.definition.requiresConsent || authorization.consentGranted else {
        return failure(
          requestID: request.requestID,
          status: .denied,
          code: "route_consent_required",
          message: "This collection method requires explicit confirmation for this run.")
      }
      guard pendingCollection == nil, activeCollection == nil else {
        return failure(
          requestID: request.requestID,
          status: .busy,
          code: "worker_busy",
          message: "The collector worker already has an active operation.")
      }
      guard let broker else {
        return failure(
          requestID: request.requestID,
          status: .denied,
          code: "configuration_broker_unavailable",
          message: "The one-operation configuration broker is unavailable.")
      }

      let cleanupController = CollectorWorkerCleanupController()
      let hardTerminationTask = Self.makeHardTerminationTask(
        budgetMilliseconds: request.budgetMilliseconds,
        cleanupController: cleanupController)
      pendingCollection = PendingCollection(
        requestID: request.requestID,
        hardTerminationTask: hardTerminationTask,
        cleanupController: cleanupController,
        cancelled: false)
      let brokeredEnvironment: [String: String]
      do {
        brokeredEnvironment = try await broker.resolve(
          request.requestID,
          authorization,
          route.definition)
      } catch {
        if pendingCollection?.requestID == request.requestID {
          pendingCollection?.hardTerminationTask.cancel()
          pendingCollection = nil
        }
        return failure(
          requestID: request.requestID,
          status: .denied,
          code: "configuration_lease_denied",
          message: "The App rejected the one-operation configuration lease.")
      }
      guard let pending = pendingCollection,
            pending.requestID == request.requestID,
            !pending.cancelled
      else {
        if pendingCollection?.requestID == request.requestID {
          pendingCollection?.hardTerminationTask.cancel()
          pendingCollection = nil
        }
        return failure(
          requestID: request.requestID,
          status: .cancelled,
          code: "cancellation_requested",
          message: "Collection was cancelled before provider execution.")
      }
      let environment = route.environment(
        processEnvironment: ProcessInfo.processInfo.environment,
        brokeredEnvironment: brokeredEnvironment)
      let processEnvironmentLease: CollectorWorkerProcessEnvironmentLease
      do {
        processEnvironmentLease = try CollectorWorkerProcessEnvironmentLease(
          allowedKeys: route.definition.allowedConfigurationKeys,
          values: brokeredEnvironment)
      } catch {
        pending.hardTerminationTask.cancel()
        if pendingCollection?.requestID == request.requestID {
          pendingCollection = nil
        }
        return failure(
          requestID: request.requestID,
          status: .denied,
          code: "process_environment_lease_failed",
          message: "The worker could not install the one-operation configuration lease.")
      }
      let collector = CodexBarCollector(
        configuration: CollectorConfiguration(
          runtime: .app,
          environment: environment,
          webTimeout: min(
            60,
            max(1, Double(request.budgetMilliseconds) / 1_000)),
          costUsageHistoryDays: 30),
        policy: route.exactPolicy(for: collectorRequest))
      pending.cleanupController.install {
        await collector.shutdown()
      }
      return await collect(
        collectorRequest,
        collector: collector,
        requestID: request.requestID,
        budgetMilliseconds: request.budgetMilliseconds,
        hardTerminationTask: pending.hardTerminationTask,
        cleanupController: pending.cleanupController,
        processEnvironmentLease: processEnvironmentLease)
    case .cancel:
      guard let cancellationRequestID = request.cancellationRequestID else {
        return failure(
          requestID: request.requestID,
          status: .invalidRequest,
          code: "missing_cancellation_target",
          message: "The cancellation envelope did not contain a target.")
      }
      if pendingCollection?.requestID == cancellationRequestID {
        pendingCollection?.cancelled = true
        return failure(
          requestID: request.requestID,
          status: .cancelled,
          code: "cancellation_requested",
          message: "Cancellation was recorded before provider execution.")
      }
      guard activeCollection?.requestID == cancellationRequestID else {
        return failure(
          requestID: request.requestID,
          status: .cancelled,
          code: "operation_not_active",
          message: "The requested operation is no longer active.")
      }
      guard let activeCollection else {
        return failure(
          requestID: request.requestID,
          status: .cancelled,
          code: "operation_not_active",
          message: "The requested operation is no longer active.")
      }
      activeCollection.task.cancel()
      Task {
        await activeCollection.cleanupController.run()
      }
      return failure(
        requestID: request.requestID,
        status: .cancelled,
        code: "cancellation_requested",
        message: "Cancellation was forwarded to the active collector operation.")
    }
  }

  private func collect(
    _ request: CollectorRequest,
    collector: CodexBarCollector,
    requestID: UUID,
    budgetMilliseconds: Int,
    hardTerminationTask: Task<Void, Never>,
    cleanupController: CollectorWorkerCleanupController,
    processEnvironmentLease: CollectorWorkerProcessEnvironmentLease
  ) async -> CollectorWireReply {
    defer {
      processEnvironmentLease.restore()
    }
    let task = Task {
      await collector.collect(request)
    }
    let deadlineTask = Task {
      try? await Task.sleep(for: .milliseconds(budgetMilliseconds))
      guard !Task.isCancelled else { return }
      task.cancel()
      await cleanupController.run()
    }
    activeCollection = ActiveCollection(
      requestID: requestID,
      task: task,
      deadlineTask: deadlineTask,
      hardTerminationTask: hardTerminationTask,
      cleanupController: cleanupController)
    if pendingCollection?.requestID == requestID {
      pendingCollection = nil
    }

    let outcome = await task.value
    deadlineTask.cancel()
    await cleanupController.run()
    hardTerminationTask.cancel()
    if activeCollection?.requestID == requestID {
      activeCollection = nil
    }

    let status: CollectorWireStatus
    switch outcome.failure?.code {
    case nil:
      status = .success
    case "request_policy_denied", "planning_policy_denied",
         "no_allowed_available_strategy", "strategy_policy_denied":
      status = .denied
    case "cancelled":
      status = .cancelled
    default:
      status = .internalFailure
    }
    return CollectorWireReply(
      requestID: requestID,
      status: status,
      outcome: outcome)
  }

  /// A non-cooperative CLI/browser/Core path must not keep the shared XPC
  /// worker alive beyond the operation budget. App-side XPC reconnects launch
  /// a fresh worker after this process exits.
  nonisolated private static func makeHardTerminationTask(
    budgetMilliseconds: Int,
    cleanupController: CollectorWorkerCleanupController
  ) -> Task<Void, Never> {
    Task.detached(priority: .utility) {
      do {
        try await Task.sleep(for: .milliseconds(budgetMilliseconds))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      let cleanupTask = Task.detached(priority: .utility) {
        await cleanupController.run()
      }
      do {
        try await Task.sleep(for: .seconds(2))
      } catch {
        cleanupTask.cancel()
        return
      }
      cleanupTask.cancel()
      guard !Task.isCancelled else { return }
      if collectorWorkerOwnsProcessGroup {
        let processGroup = getpgrp()
        if processGroup == getpid() {
          killpg(processGroup, SIGKILL)
        }
      }
      Darwin._exit(124)
    }
  }

  private func register(_ requestID: UUID) -> Bool {
    guard recentRequestIDSet.insert(requestID).inserted else { return false }
    recentRequestIDs.append(requestID)
    if recentRequestIDs.count > 256 {
      let removed = recentRequestIDs.removeFirst()
      recentRequestIDSet.remove(removed)
    }
    return true
  }

  private func failure(
    requestID: UUID,
    status: CollectorWireStatus,
    code: String,
    message: String
  ) -> CollectorWireReply {
    CollectorWireReply(
      requestID: requestID,
      status: status,
      failure: CollectorWireFailure(code: code, message: message))
  }

  nonisolated private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

private final class CollectorWorkerCleanupController: @unchecked Sendable {
  private let lock = NSLock()
  private var cleanup: (@Sendable () async -> Void)?
  private var cleanupRequested = false

  func install(_ cleanup: @escaping @Sendable () async -> Void) {
    let runImmediately = lock.withLock {
      if cleanupRequested {
        return true
      }
      self.cleanup = cleanup
      return false
    }
    if runImmediately {
      Task {
        await cleanup()
      }
    }
  }

  func run() async {
    let cleanup: (@Sendable () async -> Void)? = lock.withLock {
      cleanupRequested = true
      let cleanup = self.cleanup
      self.cleanup = nil
      return cleanup
    }
    await cleanup?()
  }
}

private final class CollectorWorkerProcessEnvironmentLease:
  @unchecked Sendable
{
  private struct Entry {
    let key: String
    let originalValue: String?
  }

  private let entries: [Entry]
  private var restored = false

  init(allowedKeys: [String], values: [String: String]) throws {
    let keys = Array(Set(allowedKeys)).sorted()
    entries = keys.map {
      Entry(
        key: $0,
        originalValue: ProcessInfo.processInfo.environment[$0])
    }
    do {
      for key in keys {
        guard unsetenv(key) == 0 else {
          throw CollectorWorkerProcessEnvironmentLeaseError.mutationFailed
        }
        if let value = values[key], !value.isEmpty {
          guard setenv(key, value, 1) == 0 else {
            throw CollectorWorkerProcessEnvironmentLeaseError.mutationFailed
          }
        }
      }
    } catch {
      restore()
      throw error
    }
  }

  func restore() {
    guard !restored else { return }
    restored = true
    for entry in entries {
      if let originalValue = entry.originalValue {
        setenv(entry.key, originalValue, 1)
      } else {
        unsetenv(entry.key)
      }
    }
  }

  deinit {
    restore()
  }
}

private enum CollectorWorkerProcessEnvironmentLeaseError: Error {
  case mutationFailed
}

private struct CollectorWorkerAuthorizedRoute: Sendable {
  let definition: CollectorLiveRouteDefinition
  let manifestDigest: String

  func matches(
    _ request: CollectorRequest,
    authorization: CollectorRouteAuthorization
  ) -> Bool {
    definition.id == authorization.routeID
      && definition.provider == request.provider
      && request.account.isAmbient
      && definition.source == request.source
      && definition.includeCredits == request.includeCredits
      && definition.includeOptionalUsage == request.includeOptionalUsage
      && definition.interaction == request.interaction
      && definition.strategyID == authorization.expectedStrategyID
      && definition.strategyKind == authorization.expectedStrategyKind
      && manifestDigest == authorization.manifestDigest
      && definition.upstreamPin == authorization.upstreamPin
      && authorization.liveCatalogRevision == CollectorLiveRouteCatalog.revision
      && definition.upstreamPin == CollectorWireIdentity.codexBarUpstreamPin
  }

  func environment(
    processEnvironment: [String: String],
    brokeredEnvironment: [String: String]
  ) -> [String: String] {
    var result = processEnvironment.filter {
      collectorWorkerSafeAmbientEnvironmentKeys.contains($0.key)
    }
    let allowedKeys = Set(definition.allowedConfigurationKeys)
    for (key, value) in brokeredEnvironment
    where allowedKeys.contains(key) && !value.isEmpty {
      result[key] = value
    }
    return result
  }

  func exactPolicy(for request: CollectorRequest) -> StaticCollectorSourcePolicy {
    let requestRule = CollectorRequestRule(
      id: "\(definition.id).request",
      provider: definition.provider,
      account: .ambient,
      source: definition.source,
      runtime: .app,
      includeCredits: definition.includeCredits,
      includeOptionalUsage: definition.includeOptionalUsage,
      interaction: definition.interaction,
      allow: true,
      reason: "Allowed by the exact one-operation Dashis live route.")
    let planningRule = CollectorPlanningRule(
      id: "\(definition.id).planning",
      provider: definition.provider,
      account: .ambient,
      source: definition.source,
      runtime: .app,
      includeCredits: definition.includeCredits,
      includeOptionalUsage: definition.includeOptionalUsage,
      interaction: definition.interaction,
      allow: true,
      reason: "Exact source planning is allowed for this operation.")
    let strategyRule = CollectorStrategyRule(
      id: "\(definition.id).strategy",
      provider: definition.provider,
      account: .ambient,
      source: definition.source,
      runtime: .app,
      includeCredits: definition.includeCredits,
      includeOptionalUsage: definition.includeOptionalUsage,
      interaction: definition.interaction,
      strategyID: definition.strategyID,
      kind: definition.strategyKind,
      allow: true,
      reason: "Only the route's exact pinned strategy is allowed.")
    return StaticCollectorSourcePolicy(
      allowedCapabilities: Set(CollectorCapability.allCases),
      requestRules: [requestRule],
      planningRules: [planningRule],
      strategyRules: [strategyRule])
  }
}

private struct CollectorWorkerRouteRegistry: Sendable {
  static let production: CollectorWorkerRouteRegistry = {
    let routes = CollectorLiveRouteCatalog.routes.map {
      CollectorWorkerAuthorizedRoute(
        definition: $0,
        manifestDigest: sha256($0.manifestMaterial))
    }
    precondition(
      Set(routes.map(\.definition.id)).count == routes.count,
      "Live collector route IDs must be unique.")
    return CollectorWorkerRouteRegistry(routes: routes)
  }()

  let routes: [CollectorWorkerAuthorizedRoute]

  var liveRouteCount: Int {
    routes.count
  }

  func resolve(
    _ request: CollectorRequest,
    authorization: CollectorRouteAuthorization
  ) -> CollectorWorkerAuthorizedRoute? {
    routes.first {
      $0.definition.id == authorization.routeID
        && $0.matches(request, authorization: authorization)
    }
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
