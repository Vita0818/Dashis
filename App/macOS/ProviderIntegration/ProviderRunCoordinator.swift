import Foundation

struct ProviderCollectionCommand: Sendable {
  let target: CollectionTargetKey
  let routeID: String?
  let interaction: ProviderCollectionInteraction
  let budgetMilliseconds: Int
  let nativeInput: NativeProviderCollectionInput?
  let collectorEnvironment: [String: String]
  let collectorConsentGranted: Bool

  init(
    target: CollectionTargetKey,
    routeID: String? = nil,
    interaction: ProviderCollectionInteraction,
    budgetMilliseconds: Int,
    nativeInput: NativeProviderCollectionInput? = nil,
    collectorEnvironment: [String: String] = [:],
    collectorConsentGranted: Bool = false
  ) {
    self.target = target
    self.routeID = routeID
    self.interaction = interaction
    self.budgetMilliseconds = min(max(1, budgetMilliseconds), 120_000)
    self.nativeInput = nativeInput
    self.collectorEnvironment = collectorEnvironment
    self.collectorConsentGranted = collectorConsentGranted
  }
}

enum ProviderCollectionInteraction: String, Codable, Sendable {
  case background
  case userInitiated
}

struct ProviderExecutionContext: Sendable {
  let command: ProviderCollectionCommand
  let run: ProviderRunIdentity
  let route: ProviderRoute
}

enum ProviderRunResult: Sendable {
  case completed(ProviderObservation)
  case superseded
  case cancelled
  case failed(code: String)
}

enum ProviderRunCoordinatorError: Error, Equatable {
  case invalidObservationIdentity
  case logicalDeadlineExceeded
}

typealias ProviderRouteExecutor =
  @Sendable (ProviderRoute, ProviderExecutionContext) async throws
    -> ProviderObservation

actor ProviderRunCoordinator {
  private struct ActiveRun {
    let runID: UUID
    let generation: Int
    let task: Task<ProviderObservation, Error>
  }

  private let registry: ProviderRouteRegistry
  private let executor: ProviderRouteExecutor
  private var generations: [CollectionTargetKey: Int] = [:]
  private var activeRuns: [CollectionTargetKey: ActiveRun] = [:]

  init(
    registry: ProviderRouteRegistry,
    executor: @escaping ProviderRouteExecutor
  ) {
    self.registry = registry
    self.executor = executor
  }

  func run(_ command: ProviderCollectionCommand) async -> ProviderRunResult {
    let target = command.target
    activeRuns[target]?.task.cancel()
    let generation = (generations[target] ?? 0) + 1
    generations[target] = generation

    let route: ProviderRoute
    do {
      if let routeID = command.routeID {
        route = try registry.resolve(routeID: routeID, target: target)
      } else {
        route = try registry.resolve(target)
      }
    } catch {
      return .failed(code: "route_unavailable")
    }

    let identity = ProviderRunIdentity(generation: generation)
    let context = ProviderExecutionContext(
      command: command,
      run: identity,
      route: route)
    let executor = self.executor
    let task = Task {
      try await executor(route, context)
    }
    activeRuns[target] = ActiveRun(
      runID: identity.runID,
      generation: generation,
      task: task)

    do {
      let observation = try await ProviderRunAwaiter(task: task).value(
        budgetMilliseconds: command.budgetMilliseconds)
      guard let active = activeRuns[target],
            active.runID == identity.runID,
            active.generation == generations[target]
      else {
        return .superseded
      }
      activeRuns[target] = nil
      guard observation.target == target,
            observation.run.runID == identity.runID,
            observation.run.generation == generation
      else {
        return .failed(code: "invalid_observation_identity")
      }
      let deadline = identity.startedAt.addingTimeInterval(
        Double(command.budgetMilliseconds) / 1_000)
      guard observation.finishedAt <= deadline else {
        return .failed(code: "logical_deadline_exceeded")
      }
      return .completed(observation)
    } catch is CancellationError {
      guard activeRuns[target]?.runID == identity.runID else {
        return .superseded
      }
      activeRuns[target] = nil
      return .cancelled
    } catch {
      guard activeRuns[target]?.runID == identity.runID else {
        return .superseded
      }
      activeRuns[target] = nil
      return .failed(code: Self.failureCode(error))
    }
  }

  func invalidate(_ target: CollectionTargetKey) {
    generations[target] = (generations[target] ?? 0) + 1
    activeRuns.removeValue(forKey: target)?.task.cancel()
  }

  func shutdown() {
    for run in activeRuns.values {
      run.task.cancel()
    }
    activeRuns.removeAll()
  }

  private nonisolated static func failureCode(_ error: Error) -> String {
    if let coordinator = error as? ProviderRunCoordinatorError {
      switch coordinator {
      case .logicalDeadlineExceeded: return "logical_deadline_exceeded"
      case .invalidObservationIdentity: return "invalid_observation_identity"
      }
    }
    if let runtime = error as? ProviderCollectionRuntimeError {
      switch runtime {
      case .interactionMismatch: return "interaction_not_authorized"
      case .nativeAdapterNotMigrated: return "native_adapter_not_migrated"
      case .collectorRouteMissingManifest: return "collector_manifest_missing"
      case let .workerDenied(code): return "worker_denied_\(Self.safeCode(code))"
      case let .workerFailed(code): return "worker_failed_\(Self.safeCode(code))"
      case .readinessMismatch: return "worker_readiness_mismatch"
      }
    }
    if let native = error as? NativeProviderObservationExecutorError {
      switch native {
      case .missingInput: return "native_input_missing"
      case .inputDoesNotMatchRoute: return "native_input_route_mismatch"
      case .accountBindingMismatch: return "native_account_binding_mismatch"
      case .scopeIdentityMismatch: return "native_scope_identity_mismatch"
      }
    }
    if let validation = error as? CollectorOutcomeValidationError {
      return "collector_validation_\(String(describing: validation))"
    }
    if let client = error as? CollectorWorkerClientError {
      switch client {
      case .deadlineExceeded: return "worker_deadline_exceeded"
      case .cancelled: return "worker_cancelled"
      case .transport: return "worker_transport_failure"
      case .invalidReply: return "worker_invalid_reply"
      }
    }
    return "provider_collection_failed"
  }

  private nonisolated static func safeCode(_ value: String) -> String {
    let scalars = value.unicodeScalars.prefix(128)
    let normalized = String(String.UnicodeScalarView(scalars)).map { character in
      character.isLetter || character.isNumber || character == "_" || character == "-"
        ? character
        : "_"
    }
    return String(normalized)
  }
}

private final class ProviderRunAwaiter: @unchecked Sendable {
  private let lock = NSLock()
  private let task: Task<ProviderObservation, Error>
  private var continuation:
    CheckedContinuation<ProviderObservation, Error>?
  private var pendingResult: Result<ProviderObservation, Error>?
  private var deadlineTask: Task<Void, Never>?
  private var completed = false

  init(task: Task<ProviderObservation, Error>) {
    self.task = task
  }

  func value(budgetMilliseconds: Int) async throws -> ProviderObservation {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        install(
          continuation,
          budgetMilliseconds: budgetMilliseconds)
      }
    } onCancel: {
      if self.resolve(.failure(CancellationError())) {
        self.task.cancel()
      }
    }
  }

  private func install(
    _ continuation: CheckedContinuation<ProviderObservation, Error>,
    budgetMilliseconds: Int
  ) {
    let pending: Result<ProviderObservation, Error>?
    lock.lock()
    if completed {
      pending = pendingResult
      pendingResult = nil
    } else {
      self.continuation = continuation
      pending = nil
    }
    lock.unlock()
    if let pending {
      continuation.resume(with: pending)
      return
    }

    let operationTask = task
    Task { [weak self, operationTask] in
      do {
        self?.resolve(.success(try await operationTask.value))
      } catch {
        self?.resolve(.failure(error))
      }
    }
    let deadlineTask = Task { [weak self, operationTask] in
      try? await Task.sleep(for: .milliseconds(budgetMilliseconds))
      guard !Task.isCancelled else { return }
      if self?.resolve(.failure(
        ProviderRunCoordinatorError.logicalDeadlineExceeded)) == true
      {
        operationTask.cancel()
      }
    }
    lock.lock()
    if completed {
      lock.unlock()
      deadlineTask.cancel()
    } else {
      self.deadlineTask = deadlineTask
      lock.unlock()
    }
  }

  @discardableResult
  private func resolve(
    _ result: Result<ProviderObservation, Error>
  ) -> Bool {
    let continuation: CheckedContinuation<ProviderObservation, Error>?
    let deadlineTask: Task<Void, Never>?
    lock.lock()
    guard !completed else {
      lock.unlock()
      return false
    }
    completed = true
    continuation = self.continuation
    self.continuation = nil
    if continuation == nil {
      pendingResult = result
    }
    deadlineTask = self.deadlineTask
    self.deadlineTask = nil
    lock.unlock()
    deadlineTask?.cancel()
    continuation?.resume(with: result)
    return true
  }
}
