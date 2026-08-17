import DashisCollectorContract
import Foundation

struct CollectionBackendReadiness: Equatable, Sendable {
  let wireVersion: Int
  let outcomeSchemaVersion: Int
  let upstreamPin: String
  let providerCount: Int
  let rolloutCatalogRevision: String
  let stagedProviderCount: Int
  let stagedStrategyCount: Int
  let stagedBindingCount: Int
  let liveRouteCount: Int
  let defaultDenyVerified: Bool
}

enum ProviderCollectionRuntimeError: Error, Equatable {
  case nativeAdapterNotMigrated(String)
  case collectorRouteMissingManifest(String)
  case interactionMismatch
  case workerDenied(String)
  case workerFailed(String)
  case readinessMismatch(String)
}

typealias NativeObservationExecutor =
  @Sendable (NativeRouteStep, ProviderExecutionContext) async throws
    -> ProviderObservation

enum NativeProviderCollectionInput: Sendable {
  case codexPersonal
  case codexEnterprise(
    accountID: UUID,
    apiKey: String,
    workspaceID: String,
    days: Int)
  case claudeLocal(snapshotURL: URL, now: Date)
  case googleConsumer(
    label: String,
    observedAt: Date,
    used: Double?,
    limit: Double?,
    remaining: Double?,
    unit: String)
  case geminiProject(
    accountID: UUID,
    projectID: String,
    accessToken: GoogleSessionAccessToken,
    selectedQuotaIDs: Set<String>?,
    observationDate: Date?)
  case openRouterAccount(
    accountID: UUID,
    apiKey: String,
    generationID: String?,
    analyticsDays: Int)
  case openRouterKey(accountID: UUID, apiKey: String)

  func matches(_ accountSlot: ProviderAccountSlot) -> Bool {
    let boundAccountID: UUID?
    switch self {
    case .codexPersonal, .claudeLocal, .googleConsumer:
      boundAccountID = nil
    case let .codexEnterprise(accountID, _, _, _),
         let .geminiProject(accountID, _, _, _, _),
         let .openRouterAccount(accountID, _, _, _),
         let .openRouterKey(accountID, _):
      boundAccountID = accountID
    }
    switch accountSlot {
    case .ambient:
      return boundAccountID == nil
    case let .selected(accountID):
      return boundAccountID == accountID
    }
  }
}

enum NativeProviderObservationExecutorError: Error, Equatable {
  case missingInput(String)
  case inputDoesNotMatchRoute(String)
  case accountBindingMismatch
  case scopeIdentityMismatch
}

struct NativeProviderObservationExecutor: @unchecked Sendable {
  let codex: CodexUsageClient
  let claude: ClaudeUsageClient
  let googleConsumer: GoogleConsumerUsageClient
  let googleProject: GeminiAPIProjectUsageClient
  let openRouter: OpenRouterUsageClient

  func execute(
    _ step: NativeRouteStep,
    context: ProviderExecutionContext
  ) async throws -> ProviderObservation {
    guard step.interaction == context.command.interaction else {
      throw ProviderCollectionRuntimeError.interactionMismatch
    }
    guard let input = context.command.nativeInput else {
      throw NativeProviderObservationExecutorError.missingInput(step.adapterID)
    }
    guard input.matches(context.command.target.accountSlot) else {
      throw NativeProviderObservationExecutorError.accountBindingMismatch
    }

    let snapshot: ProviderSnapshot
    switch (step.adapterID, input) {
    case ("dashis.codex.personal", .codexPersonal):
      snapshot = await codex.fetchPersonalSnapshot()
    case let (
      "dashis.codex.enterprise",
      .codexEnterprise(_, apiKey, workspaceID, days)):
      guard Self.scopeMatches(
        context.command.target.scopeID,
        externalID: workspaceID)
      else {
        throw NativeProviderObservationExecutorError.scopeIdentityMismatch
      }
      snapshot = await codex.fetchEnterpriseSnapshot(
        apiKey: apiKey,
        workspaceID: workspaceID,
        days: days)
    case let ("dashis.claude.status-line", .claudeLocal(snapshotURL, now)):
      snapshot = await claude.fetchSnapshot(context: .init(
        snapshotURL: snapshotURL,
        now: now))
    case let (
      "dashis.google.consumer.manual",
      .googleConsumer(label, observedAt, used, limit, remaining, unit)):
      snapshot = await googleConsumer.fetchSnapshot(context: .init(
        label: label,
        observedAt: observedAt,
        used: used,
        limit: limit,
        remaining: remaining,
        unit: unit))
    case let (
      "dashis.gemini.project",
      .geminiProject(
        _,
        projectID,
        accessToken,
        selectedQuotaIDs,
        observationDate)):
      guard Self.scopeMatches(
        context.command.target.scopeID,
        externalID: projectID)
      else {
        throw NativeProviderObservationExecutorError.scopeIdentityMismatch
      }
      snapshot = await googleProject.fetchSnapshot(context: .init(
        projectID: projectID,
        accessToken: accessToken,
        selectedQuotaIDs: selectedQuotaIDs,
        observationDate: observationDate))
    case let (
      "dashis.openrouter.account",
      .openRouterAccount(_, apiKey, generationID, analyticsDays)):
      snapshot = await openRouter.fetchManagementSnapshot(context: .init(
        apiKey: apiKey,
        generationID: generationID,
        analyticsDays: analyticsDays))
    case let ("dashis.openrouter.key", .openRouterKey(_, apiKey)):
      snapshot = await openRouter.fetchAPIKeySnapshot(apiKey: apiKey)
    default:
      throw NativeProviderObservationExecutorError.inputDoesNotMatchRoute(
        step.adapterID)
    }

    return try NativeSnapshotObservationBridge.wrap(
      snapshot,
      target: context.command.target,
      route: context.route,
      run: context.run)
  }

  private static func scopeMatches(
    _ scopeID: ProviderScopeID,
    externalID: String
  ) -> Bool {
    let normalized = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
    return !normalized.isEmpty && scopeID.rawValue == normalized
  }
}

final class ProviderCollectionRuntime: @unchecked Sendable {
  let registry: ProviderRouteRegistry
  let coordinator: ProviderRunCoordinator

  private let worker: any CollectorWorkerTransport

  init(
    registry: ProviderRouteRegistry = .production,
    worker: any CollectorWorkerTransport = CollectorWorkerClient(),
    nativeExecutor: NativeObservationExecutor? = nil
  ) {
    self.registry = registry
    self.worker = worker
    self.coordinator = ProviderRunCoordinator(registry: registry) {
      route, context in
      switch route.execution {
      case let .native(step):
        guard step.interaction == context.command.interaction else {
          throw ProviderCollectionRuntimeError.interactionMismatch
        }
        guard let input = context.command.nativeInput else {
          throw NativeProviderObservationExecutorError.missingInput(
            step.adapterID)
        }
        guard input.matches(context.command.target.accountSlot) else {
          throw NativeProviderObservationExecutorError.accountBindingMismatch
        }
        guard let nativeExecutor else {
          throw ProviderCollectionRuntimeError.nativeAdapterNotMigrated(step.adapterID)
        }
        return try await nativeExecutor(step, context)
      case let .collector(step):
        return try await Self.executeCollector(
          step: step,
          route: route,
          context: context,
          worker: worker)
      case nil:
        throw ProviderCollectionRuntimeError.workerFailed("missing_execution_step")
      }
    }
  }

  static func production(
    nativeExecutor: @escaping NativeObservationExecutor
  ) -> ProviderCollectionRuntime {
    ProviderCollectionRuntime(nativeExecutor: nativeExecutor)
  }

  func run(_ command: ProviderCollectionCommand) async -> ProviderRunResult {
    await coordinator.run(command)
  }

  func invalidate(_ target: CollectionTargetKey) async {
    await coordinator.invalidate(target)
  }

  /// Performs a side-effect-bounded end-to-end check of the XPC wiring.
  ///
  /// The negative collection probe deliberately uses an unknown route and must
  /// be rejected by the Worker before CodexBar resolves or probes any strategy.
  func verifyWiring() async throws -> CollectionBackendReadiness {
    let handshake = try await worker.handshake(budgetMilliseconds: 5_000)
    let catalog = try await worker.catalog(budgetMilliseconds: 5_000)
    guard catalog.count == 63,
          Set(catalog.map(\.id.rawValue)).count == 63
    else {
      throw ProviderCollectionRuntimeError.readinessMismatch(
        "collector_catalog_is_not_the_pinned_63_provider_set")
    }
    let catalogByID = Dictionary(
      uniqueKeysWithValues: catalog.map { ($0.id, $0) })
    guard handshake.rolloutCatalogRevision
            == CollectorRolloutCatalog.revision,
          handshake.stagedProviderCount
            == CollectorRolloutCatalog.selectedProviderIDs.count,
          handshake.stagedStrategyCount
            == CollectorRolloutCatalog.strategies.count,
          handshake.stagedBindingCount
            == CollectorRolloutCatalog.bindings.count,
          CollectorRolloutCatalog.selectedProviderIDs.allSatisfy({
            catalogByID[$0] != nil
          }),
          CollectorRolloutCatalog.bindings.allSatisfy({ binding in
            catalogByID[binding.provider]?.supportedSources.contains(
              binding.source) == true
          })
    else {
      throw ProviderCollectionRuntimeError.readinessMismatch(
        "collector_rollout_catalog_mismatch")
    }

    let deniedReply = try await worker.collect(
      CollectorRequest(
        provider: "openrouter",
        source: .api,
        includeCredits: false,
        includeOptionalUsage: false,
        interaction: .userInitiated),
      authorization: CollectorRouteAuthorization(
        routeID: "wiring.default-deny",
        expectedStrategyID: "openrouter.api",
        expectedStrategyKind: .apiToken,
        manifestDigest: String(repeating: "0", count: 64),
        upstreamPin: CollectorWireIdentity.codexBarUpstreamPin),
      configurationEnvironment: [:],
      budgetMilliseconds: 5_000)
    guard deniedReply.status == .denied,
          deniedReply.outcome == nil,
          deniedReply.failure?.code == "route_authorization_denied"
    else {
      throw ProviderCollectionRuntimeError.readinessMismatch(
        "collector_default_deny_boundary_failed")
    }

    return CollectionBackendReadiness(
      wireVersion: handshake.wireVersion,
      outcomeSchemaVersion: handshake.outcomeSchemaVersion,
      upstreamPin: handshake.upstreamPin,
      providerCount: catalog.count,
      rolloutCatalogRevision: handshake.rolloutCatalogRevision,
      stagedProviderCount: handshake.stagedProviderCount,
      stagedStrategyCount: handshake.stagedStrategyCount,
      stagedBindingCount: handshake.stagedBindingCount,
      liveRouteCount: handshake.liveRouteCount,
      defaultDenyVerified: true)
  }

  private static func executeCollector(
    step: CollectorRouteStep,
    route: ProviderRoute,
    context: ProviderExecutionContext,
    worker: any CollectorWorkerTransport
  ) async throws -> ProviderObservation {
    guard let manifestDigest = step.manifestDigest else {
      throw ProviderCollectionRuntimeError.collectorRouteMissingManifest(route.id)
    }
    let expectedInteraction: ProviderCollectionInteraction =
      step.interaction == .background ? .background : .userInitiated
    guard context.command.interaction == expectedInteraction else {
      throw ProviderCollectionRuntimeError.interactionMismatch
    }

    let account: CollectorAccountSelection
    switch context.command.target.accountSlot {
    case .ambient:
      account = .ambient
    case let .selected(accountID):
      account = CollectorAccountSelection(id: accountID)
    }
    let request = CollectorRequest(
      provider: step.provider,
      account: account,
      source: step.source,
      includeCredits: step.includeCredits,
      includeOptionalUsage: step.includeOptionalUsage,
      interaction: step.interaction)
    let authorization = CollectorRouteAuthorization(
      routeID: route.id,
      expectedStrategyID: step.exactStrategyID,
      expectedStrategyKind: step.exactStrategyKind,
      manifestDigest: manifestDigest,
      upstreamPin: step.upstreamPin,
      liveCatalogRevision: CollectorLiveRouteCatalog.revision,
      brokerLeaseID: UUID(),
      consentGranted: context.command.collectorConsentGranted)
    let reply = try await worker.collect(
      request,
      authorization: authorization,
      configurationEnvironment: context.command.collectorEnvironment,
      budgetMilliseconds: context.command.budgetMilliseconds)
    if reply.status == .denied {
      throw ProviderCollectionRuntimeError.workerDenied(
        reply.failure?.code
          ?? reply.outcome?.failure?.code
          ?? "collector_policy_denied")
    }
    guard reply.status == .success else {
      throw ProviderCollectionRuntimeError.workerFailed(
        reply.failure?.code
          ?? reply.outcome?.failure?.code
          ?? reply.status.rawValue)
    }
    guard let outcome = reply.outcome else {
      throw ProviderCollectionRuntimeError.workerFailed(
        "missing_collector_outcome")
    }
    let validated = try CollectorOutcomeValidator.validate(
      outcome,
      request: request,
      target: context.command.target,
      route: route)
    return try CollectorOutcomeMapper.map(validated, run: context.run)
  }
}
