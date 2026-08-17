import Foundation

enum ObservationEngine: String, Codable, Hashable, Sendable {
  case native
  case codexBar
}

enum ObservationConfidence: String, Codable, Hashable, Sendable {
  case exact
  case estimated
  case percentOnly
  case unknown
}

enum ObservationAccountEvidence: Hashable, Codable, Sendable {
  case ambient(slot: String)
  case selectedHostBound(UUID)
  case selectedResultVerified(UUID)
}

enum ObservationComponentKind: String, Codable, Hashable, Sendable {
  case quota
  case balance
  case metric
  case cost
}

enum ObservationComponentState: String, Codable, Hashable, Sendable {
  case observed
  case unknown
  case syntheticPlaceholder
}

struct ObservationProvenance: Equatable, Codable, Sendable {
  let engine: ObservationEngine
  let routeID: String
  let sourceKind: UsageSourceKind
  let requestedSource: String
  let resolvedSource: String?
  let strategyID: String?
  let strategyKind: String?
}

struct ObservationComponent: Equatable, Codable, Sendable {
  let kind: ObservationComponentKind
  let semanticID: String
  let label: String
  let dimensions: [String: String]
  let state: ObservationComponentState
  let used: Double?
  let limit: Double?
  let remaining: Double?
  let usedPercentage: Double?
  let remainingPercentage: Double?
  let unit: String
  let resetsAt: Date?
  let textValue: String?
  let isEstimated: Bool
  let observedAt: Date
  let confidence: ObservationConfidence
  let metadata: [String: ObservationValue]
  let provenance: ObservationProvenance
}

struct ObservationAttempt: Equatable, Codable, Sendable {
  let index: Int
  let strategyID: String
  let strategyKind: String
  let disposition: String
  let policyRuleID: String?
  let fallbackAllowed: Bool?
  let failureCode: String?
}

enum ObservationDiagnosticSeverity: String, Codable, Hashable, Sendable {
  case warning
  case error
}

struct ObservationDiagnostic: Equatable, Codable, Sendable {
  let code: String
  let message: String
  let severity: ObservationDiagnosticSeverity
}

indirect enum ObservationValue: Equatable, Codable, Sendable {
  case null
  case bool(Bool)
  case integer(Int64)
  case number(Double)
  case string(String)
  case array([ObservationValue])
  case object([String: ObservationValue])
}

struct ObservationArtifact: Equatable, Codable, Sendable {
  let schemaID: String
  let observedAt: Date
  let payload: ObservationValue
  let provenance: ObservationProvenance
}

struct ObservationSourceIdentity: Equatable, Codable, Sendable {
  let providerID: String?
  let accountEmail: String?
  let accountOrganization: String?
  let loginMethod: String?
  let providerAccountID: String?
}

struct ObservationSubscription: Equatable, Codable, Sendable {
  let expiresAt: Date?
  let renewsAt: Date?
}

struct ObservationCredentialOwnership: Equatable, Codable, Sendable {
  let historyOwnerIdentifier: String?
  let comparison: String
}

struct ObservationCreditEvent: Equatable, Codable, Sendable {
  let id: UUID
  let date: Date
  let service: String
  let creditsUsed: Double
}

struct ObservationFreshness: Equatable, Codable, Sendable {
  let collectedAt: Date
  let usageObservedAt: Date?
  let creditsObservedAt: Date?
  let costObservedAt: Date?
  let conservativeObservedAt: Date?

  init(
    collectedAt: Date,
    usageObservedAt: Date?,
    creditsObservedAt: Date?,
    costObservedAt: Date?
  ) {
    self.collectedAt = collectedAt
    self.usageObservedAt = usageObservedAt
    self.creditsObservedAt = creditsObservedAt
    self.costObservedAt = costObservedAt
    conservativeObservedAt = [
      usageObservedAt,
      creditsObservedAt,
      costObservedAt,
    ].compactMap(\.self).min()
  }
}

struct ProviderObservation: Equatable, Codable, Sendable {
  let target: CollectionTargetKey
  let run: ProviderRunIdentity
  let accountEvidence: ObservationAccountEvidence
  let provenance: ObservationProvenance
  let sourceIdentity: ObservationSourceIdentity?
  let subscription: ObservationSubscription?
  let credentialOwnership: ObservationCredentialOwnership?
  let creditEvents: [ObservationCreditEvent]
  let freshness: ObservationFreshness
  let attempts: [ObservationAttempt]
  let components: [ObservationComponent]
  let diagnostics: [ObservationDiagnostic]
  let artifacts: [ObservationArtifact]
  let startedAt: Date
  let finishedAt: Date
}

enum ProviderObservationSnapshotProjection {
  static func make(
    _ observation: ProviderObservation,
    providerID: ProviderID
  ) -> ProviderSnapshot {
    let visibleComponents = observation.components.filter {
      $0.state != .syntheticPlaceholder
    }
    let windows = visibleComponents.compactMap { component -> QuotaWindow? in
      guard component.state == .observed,
            component.kind == .quota || component.kind == .cost,
            [
              component.used,
              component.limit,
              component.remaining,
              component.usedPercentage,
              component.remainingPercentage,
            ].compactMap(\.self).contains(where: \.isFinite)
      else {
        return nil
      }
      return QuotaWindow(
        id: component.semanticID,
        label: component.label,
        used: finite(component.used),
        limit: finite(component.limit),
        remaining: finite(component.remaining),
        usedPercentage: finite(component.usedPercentage),
        remainingPercentage: finite(component.remainingPercentage),
        resetsAt: component.resetsAt,
        unit: component.unit,
        isEstimated: component.isEstimated)
    }

    let balanceComponent = visibleComponents.first {
      $0.kind == .balance
        && $0.state == .observed
        && [
          $0.used,
          $0.limit,
          $0.remaining,
        ].compactMap(\.self).contains(where: \.isFinite)
    }
    let balance = balanceComponent.map {
      ProviderBalance(
        label: $0.label,
        used: finite($0.used),
        limit: finite($0.limit),
        remaining: finite($0.remaining),
        unit: $0.unit,
        resetDescription: $0.textValue)
    }

    let metrics = visibleComponents.compactMap { component -> ProviderMetric? in
      guard component.kind == .metric,
            component.state == .observed,
            let value = [
              component.remaining,
              component.used,
              component.limit,
              component.remainingPercentage,
              component.usedPercentage,
            ].compactMap(\.self).first(where: \.isFinite)
      else {
        return nil
      }
      return ProviderMetric(
        key: component.semanticID,
        label: component.label,
        value: value,
        unit: component.unit)
    }

    var warnings = visibleComponents.enumerated().compactMap {
      index, component -> ProviderWarning? in
      guard component.state == .unknown else { return nil }
      return ProviderWarning(
        id: "collector-unknown-\(index)-\(component.semanticID)",
        message: "\(component.label) was returned without a usable numeric value.")
    }
    var partialFailures: [ProviderFailure] = []
    for (index, diagnostic) in observation.diagnostics.enumerated() {
      switch diagnostic.severity {
      case .warning:
        warnings.append(ProviderWarning(
          id: "collector-\(index)-\(diagnostic.code)",
          message: diagnostic.message))
      case .error:
        partialFailures.append(ProviderFailure(
          operation: "collector.\(index).\(diagnostic.code)",
          message: diagnostic.message))
      }
    }
    if windows.isEmpty, balance == nil, metrics.isEmpty,
       !observation.artifacts.isEmpty
    {
      warnings.append(ProviderWarning(
        id: "collector-auxiliary-data-only",
        message: "The provider returned auxiliary data that has no dashboard metric mapping yet."))
    }

    let observedAt =
      observation.freshness.conservativeObservedAt
      ?? visibleComponents.map(\.observedAt).min()
      ?? observation.freshness.collectedAt
    return ProviderSnapshot(
      providerID: providerID,
      scope: .personal("Current session"),
      sourceKind: observation.provenance.sourceKind,
      observedAt: observedAt,
      windows: windows,
      balance: balance,
      metrics: metrics,
      warnings: warnings,
      partialFailures: partialFailures)
  }

  private static func finite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
  }
}
