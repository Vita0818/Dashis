import Foundation

enum NativeSnapshotObservationError: Error, Equatable {
  case routeIsNotEnabledNative
  case routeTargetMismatch
  case providerMismatch
  case sourceKindMismatch
  case nonFiniteNumber
  case payloadTooLarge
}

enum NativeSnapshotObservationBridge {
  static func wrap(
    _ snapshot: ProviderSnapshot,
    target: CollectionTargetKey,
    route: ProviderRoute,
    run: ProviderRunIdentity,
    finishedAt: Date = Date()
  ) throws -> ProviderObservation {
    guard route.availability.isEnabled,
          case let .native(step)? = route.execution
    else {
      throw NativeSnapshotObservationError.routeIsNotEnabledNative
    }
    guard route.selector.matches(target) else {
      throw NativeSnapshotObservationError.routeTargetMismatch
    }
    guard route.legacyProviderID == snapshot.providerID else {
      throw NativeSnapshotObservationError.providerMismatch
    }
    guard route.sourceKind == snapshot.sourceKind else {
      throw NativeSnapshotObservationError.sourceKindMismatch
    }
    try validate(snapshot)

    let provenance = ObservationProvenance(
      engine: .native,
      routeID: route.id,
      sourceKind: route.sourceKind,
      requestedSource: step.adapterID,
      resolvedSource: step.adapterID,
      strategyID: nil,
      strategyKind: nil)
    let scopeDimensions = [
      "scopeKind": target.scopeKind.rawValue,
      "scopeID": target.scopeID.rawValue,
      "legacyScopeKind": snapshot.scope.kind.rawValue,
      "legacyScopeLabel": snapshot.scope.label,
    ]
    var components = snapshot.windows.map { window in
      ObservationComponent(
        kind: .quota,
        semanticID: window.id,
        label: window.label,
        dimensions: scopeDimensions,
        state: .observed,
        used: window.used,
        limit: window.limit,
        remaining: window.remaining,
        usedPercentage: window.usedPercentage,
        remainingPercentage: window.remainingPercentage,
        unit: window.unit,
        resetsAt: window.resetsAt,
        textValue: nil,
        isEstimated: window.isEstimated,
        observedAt: snapshot.observedAt,
        confidence: window.isEstimated ? .estimated : .exact,
        metadata: [:],
        provenance: provenance)
    }
    if let balance = snapshot.balance {
      components.append(ObservationComponent(
        kind: .balance,
        semanticID: "balance",
        label: balance.label,
        dimensions: scopeDimensions,
        state: .observed,
        used: balance.used,
        limit: balance.limit,
        remaining: balance.remaining,
        usedPercentage: balance.usedPercentage,
        remainingPercentage: balance.limit.flatMap { limit in
          guard limit > 0, let remaining = balance.remaining else { return nil }
          return remaining / limit * 100
        },
        unit: balance.unit,
        resetsAt: nil,
        textValue: balance.valueDescription ?? balance.resetDescription,
        isEstimated: false,
        observedAt: snapshot.observedAt,
        confidence: .exact,
        metadata: [:],
        provenance: provenance))
    }
    components += snapshot.metrics.map { metric in
      ObservationComponent(
        kind: .metric,
        semanticID: metric.key,
        label: metric.label,
        dimensions: scopeDimensions,
        state: .observed,
        used: metric.value,
        limit: nil,
        remaining: nil,
        usedPercentage: nil,
        remainingPercentage: nil,
        unit: metric.unit,
        resetsAt: nil,
        textValue: nil,
        isEstimated: false,
        observedAt: snapshot.observedAt,
        confidence: .exact,
        metadata: [:],
        provenance: provenance)
    }

    let accountEvidence: ObservationAccountEvidence
    switch target.accountSlot {
    case let .ambient(slot):
      accountEvidence = .ambient(slot: slot)
    case let .selected(id):
      accountEvidence = .selectedHostBound(id)
    }

    return ProviderObservation(
      target: target,
      run: run,
      accountEvidence: accountEvidence,
      provenance: provenance,
      sourceIdentity: nil,
      subscription: nil,
      credentialOwnership: nil,
      creditEvents: [],
      freshness: ObservationFreshness(
        collectedAt: snapshot.observedAt,
        usageObservedAt: snapshot.windows.isEmpty && snapshot.metrics.isEmpty
          ? nil
          : snapshot.observedAt,
        creditsObservedAt: snapshot.balance == nil ? nil : snapshot.observedAt,
        costObservedAt: nil),
      attempts: [],
      components: components,
      diagnostics: snapshot.warnings.map {
        ObservationDiagnostic(
          code: $0.id,
          message: $0.message,
          severity: .warning)
      } + snapshot.partialFailures.map {
        ObservationDiagnostic(
          code: $0.operation,
          message: $0.message,
          severity: .error)
      },
      artifacts: [],
      startedAt: run.startedAt,
      finishedAt: finishedAt)
  }

  private static func validate(_ snapshot: ProviderSnapshot) throws {
    let numbers =
      snapshot.windows.flatMap {
        [
          $0.used,
          $0.limit,
          $0.remaining,
          $0.usedPercentage,
          $0.remainingPercentage,
        ].compactMap(\.self)
      }
      + [
        snapshot.balance?.used,
        snapshot.balance?.limit,
        snapshot.balance?.remaining,
      ].compactMap(\.self)
      + snapshot.metrics.map(\.value)
    guard numbers.allSatisfy(\.isFinite) else {
      throw NativeSnapshotObservationError.nonFiniteNumber
    }
    guard snapshot.windows.count <= 128,
          snapshot.metrics.count <= 128,
          snapshot.warnings.count <= 128,
          snapshot.partialFailures.count <= 128,
          snapshot.warnings.allSatisfy({ $0.message.utf8.count <= 4_096 }),
          snapshot.partialFailures.allSatisfy({ $0.message.utf8.count <= 4_096 })
    else {
      throw NativeSnapshotObservationError.payloadTooLarge
    }
  }
}
