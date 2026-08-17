import DashisCollectorContract
import Foundation

enum CollectorOutcomeValidationError: Error, Equatable {
  case routeIsNotEnabled
  case routeIsNotCollector
  case requestDoesNotMatchRoute
  case schemaMismatch(Int)
  case targetMismatch
  case accountMismatch
  case accountEvidenceInsufficient
  case providerFailure(String)
  case emptySuccess
  case strategyMismatch
  case invalidAttempts
  case invalidTimestamp
  case nonFiniteNumber
  case payloadTooLarge
}

struct ValidatedCollectorOutcome: Sendable {
  fileprivate let outcome: CollectorOutcome
  fileprivate let target: CollectionTargetKey
  fileprivate let route: ProviderRoute
}

enum CollectorOutcomeValidator {
  static func validate(
    _ outcome: CollectorOutcome,
    request: CollectorRequest,
    target: CollectionTargetKey,
    route: ProviderRoute,
    now: Date = Date()
  ) throws -> ValidatedCollectorOutcome {
    guard route.availability.isEnabled else {
      throw CollectorOutcomeValidationError.routeIsNotEnabled
    }
    guard case let .collector(step)? = route.execution else {
      throw CollectorOutcomeValidationError.routeIsNotCollector
    }
    guard route.selector.matches(target),
          request.provider == step.provider,
          request.source == step.source,
          request.includeCredits == step.includeCredits,
          request.includeOptionalUsage == step.includeOptionalUsage,
          request.interaction == step.interaction
    else {
      throw CollectorOutcomeValidationError.requestDoesNotMatchRoute
    }
    guard outcome.schemaVersion == CollectorOutcome.currentSchemaVersion else {
      throw CollectorOutcomeValidationError.schemaMismatch(outcome.schemaVersion)
    }
    guard outcome.provider == request.provider,
          outcome.requestedSource == request.source
    else {
      throw CollectorOutcomeValidationError.targetMismatch
    }
    guard outcome.account == request.account else {
      throw CollectorOutcomeValidationError.accountMismatch
    }

    switch target.accountSlot {
    case .ambient:
      guard request.account.isAmbient,
            outcome.accountResolution.kind == .ambient,
            outcome.accountResolution.confirmedAccountID == nil
      else {
        throw CollectorOutcomeValidationError.accountEvidenceInsufficient
      }
    case let .selected(accountID):
      guard request.account.id == accountID,
            outcome.accountResolution.kind == .resultVerified,
            outcome.accountResolution.confirmedAccountID == accountID
      else {
        throw CollectorOutcomeValidationError.accountEvidenceInsufficient
      }
    }

    if let failure = outcome.failure {
      guard outcome.usage == nil, outcome.credits == nil, outcome.artifacts.isEmpty else {
        throw CollectorOutcomeValidationError.emptySuccess
      }
      throw CollectorOutcomeValidationError.providerFailure(failure.code)
    }
    let hasMeaningfulCredits = outcome.credits.map {
      $0.remaining != nil || !$0.events.isEmpty || $0.limit != nil
    } ?? false
    guard outcome.usage != nil || hasMeaningfulCredits || !outcome.artifacts.isEmpty else {
      throw CollectorOutcomeValidationError.emptySuccess
    }
    guard let resolved = outcome.resolvedSource,
          resolved.strategyID == step.exactStrategyID,
          resolved.kind == step.exactStrategyKind
    else {
      throw CollectorOutcomeValidationError.strategyMismatch
    }

    let expectedIndexes = Array(outcome.attempts.indices)
    guard outcome.attempts.map(\.index) == expectedIndexes,
          let succeededIndex = outcome.attempts.firstIndex(where: {
            $0.disposition == .succeeded
          }),
          succeededIndex == outcome.attempts.index(before: outcome.attempts.endIndex),
          outcome.attempts.filter({ $0.disposition == .succeeded }).count == 1,
          outcome.attempts[succeededIndex].strategyID == step.exactStrategyID,
          outcome.attempts[succeededIndex].kind == step.exactStrategyKind
    else {
      throw CollectorOutcomeValidationError.invalidAttempts
    }

    try self.validateTimes(outcome, now: now)
    try self.validateNumbers(outcome)
    try self.validatePayloadBounds(outcome)
    return ValidatedCollectorOutcome(outcome: outcome, target: target, route: route)
  }

  private static func validateTimes(_ outcome: CollectorOutcome, now: Date) throws {
    let maximumFuture = now.addingTimeInterval(60)
    let topLevelDates = [
      outcome.startedAt,
      outcome.finishedAt,
      outcome.freshness.collectedAt,
    ]
    guard topLevelDates.allSatisfy({ $0.timeIntervalSince1970.isFinite }),
          outcome.startedAt <= outcome.finishedAt,
          outcome.startedAt <= maximumFuture,
          outcome.finishedAt <= maximumFuture,
          outcome.freshness.collectedAt <= maximumFuture
    else {
      throw CollectorOutcomeValidationError.invalidTimestamp
    }

    let componentDates =
      [
        outcome.usage?.observedAt,
        outcome.usage?.cost?.observedAt,
        outcome.credits?.observedAt,
        outcome.credits?.limit?.observedAt,
        outcome.freshness.usageObservedAt,
        outcome.freshness.creditsObservedAt,
        outcome.freshness.costObservedAt,
        outcome.freshness.conservativeObservedAt,
      ].compactMap(\.self)
      + outcome.artifacts.map(\.observedAt)
      + (outcome.credits?.events.map(\.date) ?? [])
      + [
        outcome.credits?.limit?.observedAt,
      ].compactMap(\.self)

    guard componentDates.allSatisfy({
      $0.timeIntervalSince1970.isFinite && $0 <= maximumFuture
    }) else {
      throw CollectorOutcomeValidationError.invalidTimestamp
    }
    let scheduledDates =
      (outcome.usage?.windows.compactMap(\.resetsAt) ?? [])
      + [
        outcome.usage?.cost?.resetsAt,
        outcome.usage?.subscriptionExpiresAt,
        outcome.usage?.subscriptionRenewsAt,
        outcome.credits?.limit?.resetsAt,
      ].compactMap(\.self)
    let scheduledHorizon = 20 * 366 * 24 * 60 * 60.0
    guard scheduledDates.allSatisfy({
      $0.timeIntervalSince1970.isFinite
        && abs($0.timeIntervalSince(now)) <= scheduledHorizon
    }) else {
      throw CollectorOutcomeValidationError.invalidTimestamp
    }
    guard outcome.freshness.usageObservedAt == outcome.usage?.observedAt,
          outcome.freshness.creditsObservedAt == outcome.credits?.observedAt,
          outcome.freshness.costObservedAt == outcome.usage?.cost?.observedAt,
          outcome.freshness.conservativeObservedAt == [
            outcome.freshness.usageObservedAt,
            outcome.freshness.creditsObservedAt,
            outcome.freshness.costObservedAt,
          ].compactMap(\.self).min()
    else {
      throw CollectorOutcomeValidationError.invalidTimestamp
    }
  }

  private static func validateNumbers(_ outcome: CollectorOutcome) throws {
    var values: [Double] = []
    if let usage = outcome.usage {
      for window in usage.windows {
        values.append(window.usedPercent)
        values.append(window.remainingPercent)
        if let value = window.nextRegenPercent { values.append(value) }
      }
      if let cost = usage.cost {
        values += [cost.used, cost.limit]
        for value in [
          cost.nextRegenAmount,
          cost.personalUsed,
        ].compactMap(\.self) {
          values.append(value)
        }
      }
      var extensionCounter = NodeCounter()
      try self.validateValueTree(
        .object(usage.extensions),
        depth: 0,
        nodes: &extensionCounter)
    }
    if let credits = outcome.credits {
      if let remaining = credits.remaining { values.append(remaining) }
      values += credits.events.map(\.creditsUsed)
      if let limit = credits.limit {
        values += [limit.used, limit.limit, limit.remaining, limit.remainingPercent]
      }
    }
    guard values.allSatisfy(\.isFinite) else {
      throw CollectorOutcomeValidationError.nonFiniteNumber
    }

    var counter = NodeCounter()
    for artifact in outcome.artifacts {
      try self.validateValueTree(artifact.payload, depth: 0, nodes: &counter)
    }
  }

  private static func validatePayloadBounds(_ outcome: CollectorOutcome) throws {
    guard outcome.attempts.count <= 128,
          outcome.diagnostics.count <= 128,
          outcome.artifacts.count <= 128,
          (outcome.usage?.windows.count ?? 0) <= 128,
          (outcome.credits?.events.count ?? 0) <= 2_048,
          outcome.diagnostics.allSatisfy({
            $0.code.utf8.count <= 256 && $0.message.utf8.count <= 4_096
          }),
          outcome.attempts.allSatisfy({
            $0.strategyID.utf8.count <= 256
              && ($0.failure?.message.utf8.count ?? 0) <= 4_096
          }),
          outcome.artifacts.allSatisfy({ $0.schemaID.utf8.count <= 256 }),
          outcome.usage?.windows.allSatisfy({
            $0.id.utf8.count <= 256
              && ($0.title?.utf8.count ?? 0) <= 1_024
              && ($0.resetDescription?.utf8.count ?? 0) <= 4_096
          }) ?? true,
          outcome.credits?.events.allSatisfy({
            $0.service.utf8.count <= 1_024
          }) ?? true,
          Self.identityIsBounded(outcome.usage?.identity),
          (outcome.credentialOwnership?.historyOwnerIdentifier?.utf8.count ?? 0)
            <= 1_024
    else {
      throw CollectorOutcomeValidationError.payloadTooLarge
    }
    let data = try? JSONEncoder().encode(outcome.artifacts)
    guard let data, data.count <= 1_048_576 else {
      throw CollectorOutcomeValidationError.payloadTooLarge
    }
  }

  private static func identityIsBounded(_ identity: CollectorIdentity?) -> Bool {
    guard let identity else { return true }
    return [
      identity.providerID?.rawValue,
      identity.accountEmail,
      identity.accountOrganization,
      identity.loginMethod,
      identity.accountID,
    ].compactMap(\.self).allSatisfy { $0.utf8.count <= 1_024 }
  }

  private struct NodeCounter {
    var value = 0
  }

  private static func validateValueTree(
    _ value: CollectorValue,
    depth: Int,
    nodes: inout NodeCounter
  ) throws {
    guard depth <= 16, nodes.value < 10_000 else {
      throw CollectorOutcomeValidationError.payloadTooLarge
    }
    nodes.value += 1
    switch value {
    case .null, .bool, .integer:
      break
    case let .number(number):
      guard number.isFinite else {
        throw CollectorOutcomeValidationError.nonFiniteNumber
      }
    case let .string(string):
      guard string.utf8.count <= 65_536 else {
        throw CollectorOutcomeValidationError.payloadTooLarge
      }
    case let .array(values):
      for child in values {
        try self.validateValueTree(child, depth: depth + 1, nodes: &nodes)
      }
    case let .object(values):
      guard values.keys.allSatisfy({ $0.utf8.count <= 256 }) else {
        throw CollectorOutcomeValidationError.payloadTooLarge
      }
      for child in values.values {
        try self.validateValueTree(child, depth: depth + 1, nodes: &nodes)
      }
    }
  }
}

enum CollectorOutcomeMapper {
  static func map(
    _ validated: ValidatedCollectorOutcome,
    run: ProviderRunIdentity
  ) throws -> ProviderObservation {
    let outcome = validated.outcome
    let route = validated.route
    guard case .collector? = route.execution,
          let resolved = outcome.resolvedSource
    else {
      throw CollectorOutcomeValidationError.routeIsNotCollector
    }

    let provenance = ObservationProvenance(
      engine: .codexBar,
      routeID: route.id,
      sourceKind: route.sourceKind,
      requestedSource: outcome.requestedSource.rawValue,
      resolvedSource: resolved.label,
      strategyID: resolved.strategyID,
      strategyKind: resolved.kind.rawValue)
    var components: [ObservationComponent] = []

    if let usage = outcome.usage {
      for window in usage.windows {
        var metadata: [String: ObservationValue] = [
          "usageKnown": .bool(window.usageKnown),
          "isSyntheticPlaceholder": .bool(window.isSyntheticPlaceholder),
        ]
        if let windowMinutes = window.windowMinutes {
          metadata["windowMinutes"] = .integer(Int64(windowMinutes))
        }
        if let nextRegenPercent = window.nextRegenPercent {
          metadata["nextRegenPercent"] = .number(nextRegenPercent)
        }
        let state: ObservationComponentState
        if window.isSyntheticPlaceholder {
          state = .syntheticPlaceholder
        } else if window.usageKnown {
          state = .observed
        } else {
          state = .unknown
        }
        components.append(ObservationComponent(
          kind: .quota,
          semanticID: window.id,
          label: window.title ?? window.id,
          dimensions: ["role": window.role.rawValue],
          state: state,
          used: nil,
          limit: nil,
          remaining: nil,
          usedPercentage: window.usedPercent,
          remainingPercentage: window.remainingPercent,
          unit: "%",
          resetsAt: window.resetsAt,
          textValue: window.resetDescription,
          isEstimated: usage.confidence == .estimated,
          observedAt: usage.observedAt,
          confidence: Self.confidence(usage.confidence),
          metadata: metadata,
          provenance: provenance))
      }
      if let cost = usage.cost {
        var metadata: [String: ObservationValue] = [:]
        if let period = cost.period {
          metadata["period"] = .string(period)
        }
        if let nextRegenAmount = cost.nextRegenAmount {
          metadata["nextRegenAmount"] = .number(nextRegenAmount)
        }
        if let personalUsed = cost.personalUsed {
          metadata["personalUsed"] = .number(personalUsed)
        }
        components.append(ObservationComponent(
          kind: .cost,
          semanticID: "cost.\(cost.period ?? "current")",
          label: cost.period.map { "Cost · \($0)" } ?? "Cost",
          dimensions: [:],
          state: .observed,
          used: cost.used,
          limit: cost.limit,
          remaining: cost.limit - cost.used,
          usedPercentage: cost.limit > 0 ? cost.used / cost.limit * 100 : nil,
          remainingPercentage: cost.limit > 0
            ? (cost.limit - cost.used) / cost.limit * 100
            : nil,
          unit: cost.currencyCode,
          resetsAt: cost.resetsAt,
          textValue: nil,
          isEstimated: usage.confidence == .estimated,
          observedAt: cost.observedAt,
          confidence: Self.confidence(usage.confidence),
          metadata: metadata,
          provenance: provenance))
      }
    }

    if let credits = outcome.credits {
      if let remaining = credits.remaining {
        components.append(ObservationComponent(
          kind: .balance,
          semanticID: "credits.remaining",
          label: "Credits remaining",
          dimensions: [:],
          state: .observed,
          used: nil,
          limit: nil,
          remaining: remaining,
          usedPercentage: nil,
          remainingPercentage: nil,
          unit: "credits",
          resetsAt: nil,
          textValue: nil,
          isEstimated: false,
          observedAt: credits.observedAt,
          confidence: .exact,
          metadata: [:],
          provenance: provenance))
      }
      if let limit = credits.limit {
        components.append(ObservationComponent(
          kind: .quota,
          semanticID: "credits.limit",
          label: limit.title,
          dimensions: ["role": "creditLimit"],
          state: .observed,
          used: limit.used,
          limit: limit.limit,
          remaining: limit.remaining,
          usedPercentage: limit.limit > 0
            ? limit.used / limit.limit * 100
            : nil,
          remainingPercentage: limit.remainingPercent,
          unit: "credits",
          resetsAt: limit.resetsAt,
          textValue: nil,
          isEstimated: false,
          observedAt: limit.observedAt,
          confidence: .exact,
          metadata: ["balanceProvenance": .string("limitOnly")],
          provenance: provenance))
      }
    }

    var artifacts = outcome.artifacts.map {
      ObservationArtifact(
        schemaID: $0.schemaID,
        observedAt: $0.observedAt,
        payload: Self.value($0.payload),
        provenance: provenance)
    }
    if let usage = outcome.usage, !usage.extensions.isEmpty {
      artifacts.append(ObservationArtifact(
        schemaID: "dashis.codexbar.usage-extensions.v1",
        observedAt: usage.observedAt,
        payload: .object(usage.extensions.mapValues(Self.value)),
        provenance: provenance))
    }

    let accountEvidence: ObservationAccountEvidence
    switch validated.target.accountSlot {
    case let .ambient(slot):
      accountEvidence = .ambient(slot: slot)
    case let .selected(id):
      accountEvidence = .selectedResultVerified(id)
    }

    let sourceIdentity = outcome.usage?.identity.map {
      ObservationSourceIdentity(
        providerID: $0.providerID?.rawValue,
        accountEmail: $0.accountEmail,
        accountOrganization: $0.accountOrganization,
        loginMethod: $0.loginMethod,
        providerAccountID: $0.accountID)
    }
    let subscription: ObservationSubscription?
    if outcome.usage?.subscriptionExpiresAt != nil
      || outcome.usage?.subscriptionRenewsAt != nil
    {
      subscription = ObservationSubscription(
        expiresAt: outcome.usage?.subscriptionExpiresAt,
        renewsAt: outcome.usage?.subscriptionRenewsAt)
    } else {
      subscription = nil
    }
    let credentialOwnership = outcome.credentialOwnership.map {
      ObservationCredentialOwnership(
        historyOwnerIdentifier: $0.historyOwnerIdentifier,
        comparison: $0.comparison.rawValue)
    }

    return ProviderObservation(
      target: validated.target,
      run: run,
      accountEvidence: accountEvidence,
      provenance: provenance,
      sourceIdentity: sourceIdentity,
      subscription: subscription,
      credentialOwnership: credentialOwnership,
      creditEvents: outcome.credits?.events.map {
        ObservationCreditEvent(
          id: $0.id,
          date: $0.date,
          service: $0.service,
          creditsUsed: $0.creditsUsed)
      } ?? [],
      freshness: ObservationFreshness(
        collectedAt: outcome.freshness.collectedAt,
        usageObservedAt: outcome.freshness.usageObservedAt,
        creditsObservedAt: outcome.freshness.creditsObservedAt,
        costObservedAt: outcome.freshness.costObservedAt),
      attempts: outcome.attempts.map {
        ObservationAttempt(
          index: $0.index,
          strategyID: $0.strategyID,
          strategyKind: $0.kind.rawValue,
          disposition: $0.disposition.rawValue,
          policyRuleID: $0.policyRuleID,
          fallbackAllowed: $0.fallbackAllowed,
          failureCode: $0.failure?.code)
      },
      components: components,
      diagnostics: outcome.diagnostics.map {
        ObservationDiagnostic(
          code: $0.code,
          message: $0.message,
          severity: .warning)
      },
      artifacts: artifacts,
      startedAt: outcome.startedAt,
      finishedAt: outcome.finishedAt)
  }

  private static func confidence(
    _ confidence: CollectorDataConfidence
  ) -> ObservationConfidence {
    switch confidence {
    case .exact: .exact
    case .estimated: .estimated
    case .percentOnly: .percentOnly
    case .unknown: .unknown
    }
  }

  private static func value(_ value: CollectorValue) -> ObservationValue {
    switch value {
    case .null: .null
    case let .bool(value): .bool(value)
    case let .integer(value): .integer(value)
    case let .number(value): .number(value)
    case let .string(value): .string(value)
    case let .array(values): .array(values.map(Self.value))
    case let .object(values): .object(values.mapValues(Self.value))
    }
  }
}
