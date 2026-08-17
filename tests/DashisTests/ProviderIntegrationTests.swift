import DashisCollectorContract
@testable import Dashis
import Foundation
import XCTest

final class ProviderIntegrationTests: XCTestCase {
  func testCollectionTargetIdentityKeepsAccountAndScopeSeparate() throws {
    let accountID = UUID()
    let selected = CollectionTargetKey(
      productID: .geminiProject,
      accountSlot: .selected(accountID),
      scopeKind: "project",
      scopeID: "project-a")
    let ambient = CollectionTargetKey(
      productID: .geminiProject,
      accountSlot: .ambient("gemini-cli-default"),
      scopeKind: "project",
      scopeID: "project-a")
    let otherScope = CollectionTargetKey(
      productID: .geminiProject,
      accountSlot: .selected(accountID),
      scopeKind: "project",
      scopeID: "project-b")

    XCTAssertNotEqual(selected, ambient)
    XCTAssertNotEqual(selected, otherScope)
    let encoded = try JSONEncoder().encode(selected)
    XCTAssertEqual(
      try JSONDecoder().decode(CollectionTargetKey.self, from: encoded),
      selected)
    XCTAssertEqual(
      try ProviderRouteRegistry.production.resolve(selected).id,
      "native.gemini.project")
    XCTAssertEqual(
      try ProviderRouteRegistry.production.resolve(otherScope).id,
      "native.gemini.project")

    let invalid = CollectionTargetKey(
      productID: .geminiProject,
      accountSlot: .selected(accountID),
      scopeKind: "project",
      scopeID: " ")
    XCTAssertThrowsError(try ProviderRouteRegistry.production.resolve(invalid)) {
      XCTAssertEqual(
        $0 as? ProviderRouteRegistryError,
        .invalidTargetIdentity)
    }
  }

  func testProductionRegistryPublishesNativeAndExactCollectorRoutes() throws {
    let registry = ProviderRouteRegistry.production
    let enabled = registry.routes.filter(\.availability.isEnabled)
    XCTAssertEqual(
      enabled.compactMap { route in
        guard case .native? = route.execution else { return nil }
        return route.id
      },
      [
        "native.claude.local",
        "native.codex.enterprise",
        "native.codex.personal",
        "native.gemini.project",
        "native.google.consumer.manual",
        "native.openrouter.account",
        "native.openrouter.key",
      ])
    let collectorRoutes = enabled.compactMap { route -> ProviderRoute? in
      guard case .collector? = route.execution else { return nil }
      return route
    }
    XCTAssertEqual(collectorRoutes.count, CollectorLiveRouteCatalog.routes.count)
    XCTAssertEqual(collectorRoutes.count, 41)
    XCTAssertEqual(Set(collectorRoutes.map(\.id)).count, 41)

    let nativeTarget = CollectionTargetKey(
      productID: .codexPersonal,
      accountSlot: .ambient("codex-desktop"),
      scopeKind: "personal",
      scopeID: "default")
    XCTAssertEqual(try registry.resolve(nativeTarget).id, "native.codex.personal")

    let disabledTarget = CollectionTargetKey(
      productID: .geminiCLI,
      accountSlot: .ambient("gemini-cli-default"),
      scopeKind: "cli",
      scopeID: "default")
    XCTAssertThrowsError(try registry.resolve(disabledTarget)) { error in
      XCTAssertEqual(
        error as? ProviderRouteRegistryError,
        .routeDisabled("collector.gemini.cli"))
    }

    let openAIRoute = try XCTUnwrap(
      CollectorLiveRouteCatalog.routes.first {
        $0.strategyID == "openai.api.balance"
      })
    let openAITarget = CollectionTargetKey(
      productID: "collector.openai",
      accountSlot: .ambient("local-session"),
      scopeKind: "usage",
      scopeID: "openai")
    XCTAssertEqual(
      try registry.resolve(routeID: openAIRoute.id, target: openAITarget).id,
      openAIRoute.id)
  }

  func testRegistryRejectsAutomaticCollectorRoute() {
    let route = ProviderRoute(
      id: "collector.invalid.auto",
      selector: ProviderRouteSelector(
        productID: .codexPersonal,
        accountMode: .ambient,
        scopeKind: "personal"),
      priority: 1,
      availability: .disabled(reason: "test"),
      execution: .collector(CollectorRouteStep(
        provider: "codex",
        source: .auto,
        exactStrategyID: "codex.oauth",
        exactStrategyKind: .oauth,
        includeCredits: false,
        includeOptionalUsage: false,
        interaction: .userInitiated,
        manifestDigest: nil,
        upstreamPin: ProviderRouteRegistry.pinnedCodexBarCommit)),
      sourceKind: .experimentalPrivate,
      legacyProviderID: nil,
      fallbackRouteID: nil,
      fallbackFailureCodes: [])

    XCTAssertThrowsError(try ProviderRouteRegistry(routes: [route])) { error in
      XCTAssertEqual(
        error as? ProviderRouteRegistryError,
        .automaticCollectorSource("collector.invalid.auto"))
    }
  }

  func testNativeSnapshotBridgePreservesRawBoundaryValues() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let target = CollectionTargetKey(
      productID: .codexPersonal,
      accountSlot: .ambient("codex-desktop"),
      scopeKind: "personal",
      scopeID: "default")
    let route = try ProviderRouteRegistry.production.resolve(target)
    let snapshot = ProviderSnapshot(
      providerID: .codex,
      scope: .personal("Pro"),
      sourceKind: .experimentalPrivate,
      observedAt: now,
      windows: [
        QuotaWindow(
          id: "weekly",
          label: "Weekly",
          used: nil,
          limit: nil,
          remaining: nil,
          usedPercentage: 125,
          remainingPercentage: -25,
          resetsAt: nil,
          unit: "%",
          isEstimated: false),
      ],
      balance: nil,
      metrics: [],
      warnings: [],
      partialFailures: [])

    let observation = try NativeSnapshotObservationBridge.wrap(
      snapshot,
      target: target,
      route: route,
      run: ProviderRunIdentity(generation: 1, startedAt: now),
      finishedAt: now)

    XCTAssertEqual(observation.components.first?.usedPercentage, 125)
    XCTAssertEqual(observation.components.first?.remainingPercentage, -25)
    XCTAssertEqual(observation.provenance.engine, .native)
  }

  func testCollectorValidatorAndMapperRequireExactProvenance() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let target = CollectionTargetKey(
      productID: .openRouterKey,
      accountSlot: .ambient("test"),
      scopeKind: "key",
      scopeID: "test-key")
    let route = try enabledCollectorRoute()
    let request = CollectorRequest(
      provider: "openrouter",
      source: .api,
      interaction: .userInitiated)
    let usage = CollectorUsage(
      observedAt: now.addingTimeInterval(-5),
      confidence: .percentOnly,
      identity: nil,
      windows: [
        CollectorWindow(
          role: .primary,
          id: "raw",
          title: "Raw",
          usedPercent: 125,
          remainingPercent: -25,
          windowMinutes: 60,
          resetsAt: now.addingTimeInterval(3_600),
          resetDescription: nil,
          nextRegenPercent: 5,
          isSyntheticPlaceholder: false,
          usageKnown: true),
        CollectorWindow(
          role: .secondary,
          id: "placeholder",
          title: "Placeholder",
          usedPercent: 0,
          remainingPercent: 100,
          windowMinutes: nil,
          resetsAt: nil,
          resetDescription: nil,
          nextRegenPercent: nil,
          isSyntheticPlaceholder: true,
          usageKnown: false),
      ],
      cost: nil,
      subscriptionExpiresAt: now.addingTimeInterval(30 * 24 * 60 * 60),
      subscriptionRenewsAt: now.addingTimeInterval(31 * 24 * 60 * 60),
      extensions: [:])
    let creditObservedAt = now.addingTimeInterval(-4)
    let creditEvent = CollectorCreditEvent(
      id: UUID(),
      date: now.addingTimeInterval(-10),
      service: "synthetic-test",
      creditsUsed: 1.25)
    let credits = CollectorCredits(
      remaining: -3,
      events: [creditEvent],
      observedAt: creditObservedAt,
      limit: nil)
    let outcome = CollectorOutcome(
      provider: "openrouter",
      account: .ambient,
      accountResolution: CollectorAccountResolution(kind: .ambient),
      requestedSource: .api,
      resolvedSource: CollectorResolvedSource(
        label: "api",
        strategyID: "openrouter.api",
        kind: .apiToken),
      startedAt: now.addingTimeInterval(-1),
      finishedAt: now,
      attempts: [
        CollectorAttempt(
          index: 0,
          strategyID: "openrouter.api",
          kind: .apiToken,
          disposition: .succeeded),
      ],
      usage: usage,
      credits: credits,
      artifacts: [],
      diagnostics: [],
      credentialOwnership: CollectorCredentialOwnership(
        historyOwnerIdentifier: "synthetic-owner",
        comparison: .notApplicable),
      freshness: CollectorFreshness(
        collectedAt: now,
        usageObservedAt: usage.observedAt,
        creditsObservedAt: creditObservedAt,
        costObservedAt: nil),
      failure: nil)

    let validated = try CollectorOutcomeValidator.validate(
      outcome,
      request: request,
      target: target,
      route: route,
      now: now)
    let mapped = try CollectorOutcomeMapper.map(
      validated,
      run: ProviderRunIdentity(generation: 1, startedAt: now.addingTimeInterval(-1)))

    XCTAssertEqual(mapped.components.first?.usedPercentage, 125)
    XCTAssertEqual(mapped.components.first?.remainingPercentage, -25)
    XCTAssertEqual(mapped.components.first?.state, .observed)
    XCTAssertEqual(mapped.components.first?.metadata["usageKnown"], .bool(true))
    XCTAssertEqual(mapped.components.first?.metadata["windowMinutes"], .integer(60))
    XCTAssertEqual(mapped.components.first?.metadata["nextRegenPercent"], .number(5))
    XCTAssertEqual(
      mapped.components.first(where: { $0.semanticID == "placeholder" })?.state,
      .syntheticPlaceholder)
    XCTAssertEqual(
      mapped.components.first(where: { $0.kind == .balance })?.remaining,
      -3)
    XCTAssertEqual(mapped.subscription?.expiresAt, usage.subscriptionExpiresAt)
    XCTAssertEqual(mapped.credentialOwnership?.comparison, "notApplicable")
    XCTAssertEqual(mapped.creditEvents.map(\.id), [creditEvent.id])
    XCTAssertEqual(mapped.provenance.strategyID, "openrouter.api")
    XCTAssertEqual(mapped.provenance.sourceKind, .officialDirect)
    let snapshot = ProviderObservationSnapshotProjection.make(
      mapped,
      providerID: "openrouter")
    XCTAssertEqual(snapshot.windows.map(\.id), ["raw"])
    XCTAssertEqual(snapshot.windows.first?.usedPercentage, 125)
    XCTAssertEqual(snapshot.balance?.remaining, -3)
    XCTAssertEqual(snapshot.observedAt, usage.observedAt)
    let encoded = try JSONEncoder().encode(mapped)
    XCTAssertEqual(
      try JSONDecoder().decode(ProviderObservation.self, from: encoded),
      mapped)
  }

  func testCollectorMapperDoesNotInventUnknownCreditBalanceFromLimit() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let target = CollectionTargetKey(
      productID: .openRouterKey,
      accountSlot: .ambient("test"),
      scopeKind: "key",
      scopeID: "test-key")
    let route = try enabledCollectorRoute()
    let request = CollectorRequest(
      provider: "openrouter",
      source: .api,
      interaction: .userInitiated)
    let limit = CollectorCreditLimit(
      title: "Credit limit",
      used: 10,
      limit: 10,
      remaining: 0,
      remainingPercent: 0,
      resetsAt: now.addingTimeInterval(3_600),
      observedAt: now.addingTimeInterval(-5))
    let credits = CollectorCredits(
      remaining: nil,
      events: [],
      observedAt: now.addingTimeInterval(-5),
      limit: limit)
    let outcome = CollectorOutcome(
      provider: "openrouter",
      account: .ambient,
      accountResolution: CollectorAccountResolution(kind: .ambient),
      requestedSource: .api,
      resolvedSource: CollectorResolvedSource(
        label: "api",
        strategyID: "openrouter.api",
        kind: .apiToken),
      startedAt: now.addingTimeInterval(-1),
      finishedAt: now,
      attempts: [
        CollectorAttempt(
          index: 0,
          strategyID: "openrouter.api",
          kind: .apiToken,
          disposition: .succeeded),
      ],
      usage: nil,
      credits: credits,
      artifacts: [],
      diagnostics: [],
      credentialOwnership: nil,
      freshness: CollectorFreshness(
        collectedAt: now,
        usageObservedAt: nil,
        creditsObservedAt: credits.observedAt,
        costObservedAt: nil),
      failure: nil)

    let validated = try CollectorOutcomeValidator.validate(
      outcome,
      request: request,
      target: target,
      route: route,
      now: now)
    let mapped = try CollectorOutcomeMapper.map(
      validated,
      run: ProviderRunIdentity(generation: 1, startedAt: now.addingTimeInterval(-1)))

    XCTAssertFalse(mapped.components.contains(where: { $0.kind == .balance }))
    let limitComponent = try XCTUnwrap(
      mapped.components.first(where: { $0.semanticID == "credits.limit" }))
    XCTAssertEqual(limitComponent.kind, .quota)
    XCTAssertEqual(limitComponent.remaining, 0)
    XCTAssertEqual(
      limitComponent.metadata["balanceProvenance"],
      .string("limitOnly"))
  }

  func testCoordinatorRejectsLateResultFromSupersededGeneration() async throws {
    let target = CollectionTargetKey(
      productID: .codexPersonal,
      accountSlot: .ambient("codex-desktop"),
      scopeKind: "personal",
      scopeID: "default")
    let registry = try ProviderRouteRegistry(routes: [
      ProviderRoute(
        id: "native.test",
        selector: ProviderRouteSelector(
          productID: .codexPersonal,
          accountMode: .ambient,
          scopeKind: "personal"),
        priority: 1,
        availability: .enabled,
        execution: .native(NativeRouteStep(adapterID: "test")),
        sourceKind: .experimentalPrivate,
        legacyProviderID: .codex,
        fallbackRouteID: nil,
        fallbackFailureCodes: []),
    ])
    let coordinator = ProviderRunCoordinator(registry: registry) { route, context in
      try await Task.sleep(for: .milliseconds(50))
      return Self.emptyObservation(route: route, context: context)
    }
    let command = ProviderCollectionCommand(
      target: target,
      interaction: .userInitiated,
      budgetMilliseconds: 1_000)
    let first = Task { await coordinator.run(command) }
    try await Task.sleep(for: .milliseconds(5))
    let second = Task { await coordinator.run(command) }

    guard case .superseded = await first.value else {
      return XCTFail("The first generation should be superseded.")
    }
    guard case .completed = await second.value else {
      return XCTFail("The newest generation should be publishable.")
    }
  }

  func testCoordinatorEnforcesWallClockDeadline() async throws {
    let target = CollectionTargetKey(
      productID: .codexPersonal,
      accountSlot: .ambient("codex-desktop"),
      scopeKind: "personal",
      scopeID: "default")
    let registry = try self.singleNativeRegistry()
    let coordinator = ProviderRunCoordinator(registry: registry) { route, context in
      try await Task.sleep(for: .seconds(5))
      return Self.emptyObservation(route: route, context: context)
    }
    let command = ProviderCollectionCommand(
      target: target,
      interaction: .userInitiated,
      budgetMilliseconds: 20)
    let clock = ContinuousClock()
    let started = clock.now

    for _ in 0..<10 {
      let result = await coordinator.run(command)
      guard case let .failed(code) = result else {
        return XCTFail("The deadline should fail the run.")
      }
      XCTAssertEqual(code, "logical_deadline_exceeded")
    }
    XCTAssertLessThan(started.duration(to: clock.now), .seconds(1))
  }

  func testCoordinatorPropagatesCallerCancellation() async throws {
    let target = CollectionTargetKey(
      productID: .codexPersonal,
      accountSlot: .ambient("codex-desktop"),
      scopeKind: "personal",
      scopeID: "default")
    let registry = try self.singleNativeRegistry()
    let probe = ProviderIntegrationCancellationProbe()
    let coordinator = ProviderRunCoordinator(registry: registry) { route, context in
      try await withTaskCancellationHandler {
        try await Task.sleep(for: .seconds(5))
        return Self.emptyObservation(route: route, context: context)
      } onCancel: {
        Task { await probe.markCancelled() }
      }
    }
    let command = ProviderCollectionCommand(
      target: target,
      interaction: .userInitiated,
      budgetMilliseconds: 5_000)
    let task = Task { await coordinator.run(command) }
    try await Task.sleep(for: .milliseconds(20))
    task.cancel()

    guard case .cancelled = await task.value else {
      return XCTFail("Cancelling run() must return cancelled.")
    }
    for _ in 0..<20 {
      if await probe.wasCancelled() { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let wasCancelled = await probe.wasCancelled()
    XCTAssertTrue(wasCancelled)
  }

  func testNativeInteractionPolicyRejectsBackgroundBeforeExecutor() async throws {
    let target = CollectionTargetKey(
      productID: .codexPersonal,
      accountSlot: .ambient("codex-desktop"),
      scopeKind: "personal",
      scopeID: "default")
    let registry = try self.singleNativeRegistry()
    let probe = ProviderIntegrationCancellationProbe()
    let runtime = ProviderCollectionRuntime(
      registry: registry,
      nativeExecutor: { _, context in
        await probe.markInvoked()
        return Self.emptyObservation(route: context.route, context: context)
      })
    let result = await runtime.coordinator.run(ProviderCollectionCommand(
      target: target,
      interaction: .background,
      budgetMilliseconds: 1_000,
      nativeInput: .codexPersonal))

    guard case let .failed(code) = result else {
      return XCTFail("Background collection should fail closed.")
    }
    XCTAssertEqual(code, "interaction_not_authorized")
    let wasInvoked = await probe.wasInvoked()
    XCTAssertFalse(wasInvoked)
  }

  func testNativeSelectedCredentialBindingRejectsWrongAccount() async throws {
    let selectedAccountID = UUID()
    let route = ProviderRoute(
      id: "native.test.openrouter-key",
      selector: ProviderRouteSelector(
        productID: .openRouterKey,
        accountMode: .selected,
        scopeKind: "key"),
      priority: 1,
      availability: .enabled,
      execution: .native(NativeRouteStep(adapterID: "test.openrouter-key")),
      sourceKind: .officialDirect,
      legacyProviderID: .openRouter,
      fallbackRouteID: nil,
      fallbackFailureCodes: [])
    let registry = try ProviderRouteRegistry(routes: [route])
    let probe = ProviderIntegrationCancellationProbe()
    let runtime = ProviderCollectionRuntime(
      registry: registry,
      nativeExecutor: { _, context in
        await probe.markInvoked()
        return Self.emptyObservation(route: context.route, context: context)
      })
    let result = await runtime.coordinator.run(ProviderCollectionCommand(
      target: CollectionTargetKey(
        productID: .openRouterKey,
        accountSlot: .selected(selectedAccountID),
        scopeKind: "key",
        scopeID: "synthetic-key-slot"),
      interaction: .userInitiated,
      budgetMilliseconds: 1_000,
      nativeInput: .openRouterKey(
        accountID: UUID(),
        apiKey: "synthetic-not-a-real-key")))

    guard case let .failed(code) = result else {
      return XCTFail("A credential bound to another account must fail closed.")
    }
    XCTAssertEqual(code, "native_account_binding_mismatch")
    let wasInvoked = await probe.wasInvoked()
    XCTAssertFalse(wasInvoked)
  }

  func testEmbeddedWorkerCatalogAndDefaultDenyWiring() async throws {
    let readiness = try await DashisProviderService().collectionRuntime.verifyWiring()

    XCTAssertEqual(readiness.wireVersion, 4)
    XCTAssertEqual(readiness.outcomeSchemaVersion, 2)
    XCTAssertEqual(
      readiness.upstreamPin,
      CollectorWireIdentity.codexBarUpstreamPin)
    XCTAssertEqual(readiness.providerCount, 63)
    XCTAssertEqual(
      readiness.rolloutCatalogRevision,
      CollectorRolloutCatalog.revision)
    XCTAssertEqual(readiness.stagedProviderCount, 34)
    XCTAssertEqual(readiness.stagedStrategyCount, 52)
    XCTAssertEqual(readiness.stagedBindingCount, 50)
    XCTAssertEqual(readiness.liveRouteCount, 41)
    XCTAssertTrue(readiness.defaultDenyVerified)
  }

  func testHostBrokerLeaseIsExactAndConsumableOnlyOnce() throws {
    let route = try XCTUnwrap(
      CollectorLiveRouteCatalog.routes.first {
        $0.strategyID == "openai.api.balance"
      })
    let requestID = UUID()
    let leaseID = UUID()
    let authorization = CollectorRouteAuthorization(
      routeID: route.id,
      expectedStrategyID: route.strategyID,
      expectedStrategyKind: route.strategyKind,
      manifestDigest: String(repeating: "a", count: 64),
      upstreamPin: route.upstreamPin,
      liveCatalogRevision: CollectorLiveRouteCatalog.revision,
      brokerLeaseID: leaseID)
    let broker = CollectorHostBrokerServer(
      requestID: requestID,
      authorization: authorization,
      route: route,
      environment: [
        "OPENAI_API_KEY": "synthetic-session-value",
        "UNDECLARED_KEY": "must-not-cross",
      ])
    let requestData = try CollectorHostBrokerCodec.encodeRequest(
      CollectorHostBrokerRequest(
        requestID: requestID,
        leaseID: leaseID,
        routeID: route.id,
        provider: route.provider,
        requestedKeys: route.allowedConfigurationKeys.sorted()))

    let first = expectation(description: "first broker resolution")
    var firstData: Data?
    var firstError: NSError?
    broker.resolve(requestData) { data, error in
      firstData = data
      firstError = error
      first.fulfill()
    }
    wait(for: [first], timeout: 1)
    XCTAssertNil(firstError)
    let reply = try CollectorHostBrokerCodec.decodeReply(
      XCTUnwrap(firstData))
    XCTAssertEqual(reply.environment, [
      "OPENAI_API_KEY": "synthetic-session-value",
    ])

    let replay = expectation(description: "broker replay rejection")
    var replayData: Data?
    var replayError: NSError?
    broker.resolve(requestData) { data, error in
      replayData = data
      replayError = error
      replay.fulfill()
    }
    wait(for: [replay], timeout: 1)
    XCTAssertNil(replayData)
    XCTAssertEqual(replayError?.domain, DashisCollectorXPC.errorDomain)
  }

  func testRuntimeClassifiesWorkerRouteAuthorizationDenial() async throws {
    let route = try enabledCollectorRoute()
    let runtime = ProviderCollectionRuntime(
      registry: try ProviderRouteRegistry(routes: [route]),
      worker: DenyingCollectorWorker())
    let result = await runtime.coordinator.run(ProviderCollectionCommand(
      target: CollectionTargetKey(
        productID: .openRouterKey,
        accountSlot: .ambient("test"),
        scopeKind: "key",
        scopeID: "test-key"),
      interaction: .userInitiated,
      budgetMilliseconds: 1_000))

    guard case let .failed(code) = result else {
      return XCTFail("The worker authorization denial must fail the run.")
    }
    XCTAssertEqual(code, "worker_denied_route_authorization_denied")
  }

  func testRuntimePreservesCollectorOutcomeFailureCode() async throws {
    let route = try enabledCollectorRoute()
    let runtime = ProviderCollectionRuntime(
      registry: try ProviderRouteRegistry(routes: [route]),
      worker: FailingOutcomeCollectorWorker())
    let result = await runtime.coordinator.run(ProviderCollectionCommand(
      target: CollectionTargetKey(
        productID: .openRouterKey,
        accountSlot: .ambient("test"),
        scopeKind: "key",
        scopeID: "test-key"),
      interaction: .userInitiated,
      budgetMilliseconds: 1_000))

    guard case let .failed(code) = result else {
      return XCTFail("The provider failure must fail the run.")
    }
    XCTAssertEqual(code, "worker_failed_fetch_failed")
  }

  func testRuntimeDispatchesExactLiveRouteAndMapsSyntheticWorkerOutcome() async throws {
    let definition = try XCTUnwrap(
      CollectorLiveRouteCatalog.routes.first {
        $0.strategyID == "openai.api.balance"
      })
    let worker = SyntheticSuccessCollectorWorker(route: definition)
    let runtime = ProviderCollectionRuntime(
      registry: .production,
      worker: worker)
    let target = CollectionTargetKey(
      productID: "collector.openai",
      accountSlot: .ambient("local-session"),
      scopeKind: "usage",
      scopeID: "openai")
    let result = await runtime.run(ProviderCollectionCommand(
      target: target,
      routeID: definition.id,
      interaction: .userInitiated,
      budgetMilliseconds: 1_000,
      collectorEnvironment: [
        "OPENAI_API_KEY": "synthetic-session-value",
      ]))

    guard case let .completed(observation) = result else {
      return XCTFail("The synthetic live route should complete, got \(result)")
    }
    XCTAssertEqual(observation.target, target)
    XCTAssertEqual(observation.provenance.engine, .codexBar)
    XCTAssertEqual(observation.provenance.routeID, definition.id)
    XCTAssertEqual(observation.provenance.strategyID, definition.strategyID)
    XCTAssertEqual(observation.components.first?.remainingPercentage, 80)
    let captured = await worker.captured()
    XCTAssertEqual(
      captured?.environment["OPENAI_API_KEY"],
      "synthetic-session-value")
    XCTAssertEqual(captured?.authorization.routeID, definition.id)
    XCTAssertEqual(captured?.authorization.consentGranted, false)
  }

  @MainActor
  func testStoreRunsConfiguredCollectorRouteAndPublishesLiveSnapshot() async throws {
    let definition = try XCTUnwrap(
      CollectorLiveRouteCatalog.routes.first {
        $0.strategyID == "openai.api.balance"
      })
    let worker = SyntheticSuccessCollectorWorker(route: definition)
    let runtime = ProviderCollectionRuntime(
      registry: .production,
      worker: worker)
    let store = DashisProviderStore(service: DashisProviderService(
      collectionRuntime: runtime))

    store.setCollectorInputValue(
      "synthetic-session-value",
      routeID: definition.id,
      key: "OPENAI_API_KEY")
    await store.runCollectorCheck(
      for: definition.provider.rawValue,
      consentGranted: false)

    let providerID = ProviderID(rawValue: definition.provider.rawValue)
    let snapshot = try XCTUnwrap(store.snapshots[providerID])
    XCTAssertEqual(snapshot.windows.first?.remainingPercentage, 80)
    XCTAssertEqual(store.provider(id: providerID.rawValue)?.primary, "80% left")
    XCTAssertEqual(
      store.observations.values.first?.provenance.routeID,
      definition.id)
    let captured = await worker.captured()
    XCTAssertEqual(
      captured?.environment["OPENAI_API_KEY"],
      "synthetic-session-value")
  }

  func testProductionRuntimeExecutesNativeManualRouteWithoutStore() async {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let target = CollectionTargetKey(
      productID: .googleConsumerManual,
      accountSlot: .ambient("google-consumer"),
      scopeKind: "consumer",
      scopeID: "default")
    let command = ProviderCollectionCommand(
      target: target,
      interaction: .userInitiated,
      budgetMilliseconds: 1_000,
      nativeInput: .googleConsumer(
        label: "Synthetic Google consumer",
        observedAt: now,
        used: 4,
        limit: 10,
        remaining: 6,
        unit: "requests"))

    let result = await DashisProviderService().collectionRuntime.coordinator.run(command)
    guard case let .completed(observation) = result else {
      return XCTFail("The production native executor should complete, got \(result)")
    }
    XCTAssertEqual(observation.target, target)
    XCTAssertEqual(observation.provenance.engine, .native)
    XCTAssertEqual(observation.components.first?.remaining, 6)
  }

  private func enabledCollectorRoute() throws -> ProviderRoute {
    let route = ProviderRoute(
      id: "collector.test.openrouter",
      selector: ProviderRouteSelector(
        productID: .openRouterKey,
        accountMode: .ambient,
        scopeKind: "key"),
      priority: 1,
      availability: .enabled,
      execution: .collector(CollectorRouteStep(
        provider: "openrouter",
        source: .api,
        exactStrategyID: "openrouter.api",
        exactStrategyKind: .apiToken,
        includeCredits: false,
        includeOptionalUsage: false,
        interaction: .userInitiated,
        manifestDigest: String(repeating: "a", count: 64),
        upstreamPin: ProviderRouteRegistry.pinnedCodexBarCommit)),
      sourceKind: .officialDirect,
      legacyProviderID: nil,
      fallbackRouteID: nil,
      fallbackFailureCodes: [])
    _ = try ProviderRouteRegistry(routes: [route])
    return route
  }

  private func singleNativeRegistry() throws -> ProviderRouteRegistry {
    try ProviderRouteRegistry(routes: [
      ProviderRoute(
        id: "native.test",
        selector: ProviderRouteSelector(
          productID: .codexPersonal,
          accountMode: .ambient,
          scopeKind: "personal"),
        priority: 1,
        availability: .enabled,
        execution: .native(NativeRouteStep(adapterID: "test")),
        sourceKind: .experimentalPrivate,
        legacyProviderID: .codex,
        fallbackRouteID: nil,
        fallbackFailureCodes: []),
    ])
  }

  private static func emptyObservation(
    route: ProviderRoute,
    context: ProviderExecutionContext
  ) -> ProviderObservation {
    let provenance = ObservationProvenance(
      engine: .native,
      routeID: route.id,
      sourceKind: route.sourceKind,
      requestedSource: "test",
      resolvedSource: "test",
      strategyID: nil,
      strategyKind: nil)
    return ProviderObservation(
      target: context.command.target,
      run: context.run,
      accountEvidence: .ambient(slot: "codex-desktop"),
      provenance: provenance,
      sourceIdentity: nil,
      subscription: nil,
      credentialOwnership: nil,
      creditEvents: [],
      freshness: ObservationFreshness(
        collectedAt: context.run.startedAt,
        usageObservedAt: nil,
        creditsObservedAt: nil,
        costObservedAt: nil),
      attempts: [],
      components: [],
      diagnostics: [],
      artifacts: [],
      startedAt: context.run.startedAt,
      finishedAt: Date())
  }
}

private struct DenyingCollectorWorker: CollectorWorkerTransport {
  func handshake(
    budgetMilliseconds: Int
  ) async throws -> CollectorWorkerHandshake {
    CollectorWorkerHandshake(
      wireVersion: CollectorWireRequest.currentWireVersion,
      outcomeSchemaVersion: CollectorOutcome.currentSchemaVersion,
      workerBundleIdentifier: DashisCollectorXPC.serviceName,
      workerBundleVersion: "test",
      maximumRequestBytes: CollectorWireLimits.maximumRequestBytes,
      maximumResponseBytes: CollectorWireLimits.maximumResponseBytes,
      upstreamPin: CollectorWireIdentity.codexBarUpstreamPin,
      rolloutCatalogRevision: CollectorRolloutCatalog.revision,
      stagedProviderCount: CollectorRolloutCatalog.selectedProviderIDs.count,
      stagedStrategyCount: CollectorRolloutCatalog.strategies.count,
      stagedBindingCount: CollectorRolloutCatalog.bindings.count,
      liveRouteCount: CollectorLiveRouteCatalog.routes.count,
      liveCatalogRevision: CollectorLiveRouteCatalog.revision,
      liveManifestSetDigest: String(repeating: "a", count: 64))
  }

  func catalog(
    budgetMilliseconds: Int
  ) async throws -> [CollectorProvider] {
    []
  }

  func collect(
    _ request: CollectorRequest,
    authorization: CollectorRouteAuthorization,
    configurationEnvironment: [String: String],
    budgetMilliseconds: Int
  ) async throws -> CollectorWireReply {
    CollectorWireReply(
      requestID: UUID(),
      status: .denied,
      failure: CollectorWireFailure(
        code: "route_authorization_denied",
        message: "Synthetic worker route denial."))
  }
}

private struct FailingOutcomeCollectorWorker: CollectorWorkerTransport {
  func handshake(
    budgetMilliseconds: Int
  ) async throws -> CollectorWorkerHandshake {
    fatalError("The collection runtime does not call handshake for a run.")
  }

  func catalog(
    budgetMilliseconds: Int
  ) async throws -> [CollectorProvider] {
    fatalError("The collection runtime does not call catalog for a run.")
  }

  func collect(
    _ request: CollectorRequest,
    authorization: CollectorRouteAuthorization,
    configurationEnvironment: [String: String],
    budgetMilliseconds: Int
  ) async throws -> CollectorWireReply {
    let now = Date()
    return CollectorWireReply(
      requestID: UUID(),
      status: .internalFailure,
      outcome: CollectorOutcome(
        provider: request.provider,
        account: request.account,
        accountResolution: CollectorAccountResolution(kind: .ambient),
        requestedSource: request.source,
        resolvedSource: nil,
        startedAt: now,
        finishedAt: now,
        attempts: [],
        usage: nil,
        credits: nil,
        artifacts: [],
        diagnostics: [],
        credentialOwnership: nil,
        freshness: CollectorFreshness(
          collectedAt: now,
          usageObservedAt: nil,
          creditsObservedAt: nil,
          costObservedAt: nil),
        failure: CollectorFailure(
          code: "fetch_failed",
          message: "Synthetic provider failure.")))
  }
}

private actor SyntheticSuccessCollectorWorker: CollectorWorkerTransport {
  struct Capture: Sendable {
    let environment: [String: String]
    let authorization: CollectorRouteAuthorization
  }

  private let route: CollectorLiveRouteDefinition
  private var lastCapture: Capture?

  init(route: CollectorLiveRouteDefinition) {
    self.route = route
  }

  func handshake(
    budgetMilliseconds: Int
  ) async throws -> CollectorWorkerHandshake {
    CollectorWorkerHandshake(
      wireVersion: CollectorWireRequest.currentWireVersion,
      outcomeSchemaVersion: CollectorOutcome.currentSchemaVersion,
      workerBundleIdentifier: DashisCollectorXPC.serviceName,
      workerBundleVersion: "synthetic",
      maximumRequestBytes: CollectorWireLimits.maximumRequestBytes,
      maximumResponseBytes: CollectorWireLimits.maximumResponseBytes,
      upstreamPin: CollectorWireIdentity.codexBarUpstreamPin,
      rolloutCatalogRevision: CollectorRolloutCatalog.revision,
      stagedProviderCount: CollectorRolloutCatalog.selectedProviderIDs.count,
      stagedStrategyCount: CollectorRolloutCatalog.strategies.count,
      stagedBindingCount: CollectorRolloutCatalog.bindings.count,
      liveRouteCount: CollectorLiveRouteCatalog.routes.count,
      liveCatalogRevision: CollectorLiveRouteCatalog.revision,
      liveManifestSetDigest: String(repeating: "a", count: 64))
  }

  func catalog(
    budgetMilliseconds: Int
  ) async throws -> [CollectorProvider] {
    []
  }

  func collect(
    _ request: CollectorRequest,
    authorization: CollectorRouteAuthorization,
    configurationEnvironment: [String: String],
    budgetMilliseconds: Int
  ) async throws -> CollectorWireReply {
    lastCapture = Capture(
      environment: configurationEnvironment,
      authorization: authorization)
    let now = Date()
    let usage = CollectorUsage(
      observedAt: now,
      confidence: .percentOnly,
      identity: nil,
      windows: [
        CollectorWindow(
          role: .primary,
          id: "synthetic-window",
          title: "Synthetic usage window",
          usedPercent: 20,
          remainingPercent: 80,
          windowMinutes: 300,
          resetsAt: now.addingTimeInterval(3_600),
          resetDescription: nil,
          nextRegenPercent: nil,
          isSyntheticPlaceholder: false,
          usageKnown: true),
      ],
      cost: nil,
      subscriptionExpiresAt: nil,
      subscriptionRenewsAt: nil,
      extensions: [:])
    return CollectorWireReply(
      requestID: UUID(),
      status: .success,
      outcome: CollectorOutcome(
        provider: request.provider,
        account: request.account,
        accountResolution: CollectorAccountResolution(kind: .ambient),
        requestedSource: request.source,
        resolvedSource: CollectorResolvedSource(
          label: route.source.rawValue,
          strategyID: route.strategyID,
          kind: route.strategyKind),
        startedAt: now,
        finishedAt: now,
        attempts: [
          CollectorAttempt(
            index: 0,
            strategyID: route.strategyID,
            kind: route.strategyKind,
            disposition: .succeeded),
        ],
        usage: usage,
        credits: nil,
        artifacts: [],
        diagnostics: [],
        credentialOwnership: nil,
        freshness: CollectorFreshness(
          collectedAt: now,
          usageObservedAt: now,
          creditsObservedAt: nil,
          costObservedAt: nil),
        failure: nil))
  }

  func captured() -> Capture? {
    lastCapture
  }
}

private actor ProviderIntegrationCancellationProbe {
  private var cancelled = false
  private var invoked = false

  func markCancelled() {
    cancelled = true
  }

  func wasCancelled() -> Bool {
    cancelled
  }

  func markInvoked() {
    invoked = true
  }

  func wasInvoked() -> Bool {
    invoked
  }
}
