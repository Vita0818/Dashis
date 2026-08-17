import DashisCollectorContract
import CryptoKit
import Foundation

enum ProviderRouteAccountMode: String, Codable, Hashable, Sendable {
  case ambient
  case selected
}

struct ProviderRouteSelector: Hashable, Codable, Sendable {
  let productID: ProviderProductID
  let accountMode: ProviderRouteAccountMode
  let scopeKind: ProviderRouteScopeKind

  func matches(_ target: CollectionTargetKey) -> Bool {
    productID == target.productID
      && accountMode == target.accountSlot.mode
      && scopeKind == target.scopeKind
  }
}

struct NativeRouteStep: Hashable, Codable, Sendable {
  let adapterID: String
  let interaction: ProviderCollectionInteraction

  init(
    adapterID: String,
    interaction: ProviderCollectionInteraction = .userInitiated
  ) {
    self.adapterID = adapterID
    self.interaction = interaction
  }
}

struct CollectorRouteStep: Equatable, Codable, Sendable {
  let provider: CollectorProviderID
  let source: CollectorSourceMode
  let exactStrategyID: String
  let exactStrategyKind: CollectorStrategyKind
  let includeCredits: Bool
  let includeOptionalUsage: Bool
  let interaction: CollectorInteraction
  let manifestDigest: String?
  let upstreamPin: String
}

enum ProviderRouteExecution: Equatable, Codable, Sendable {
  case native(NativeRouteStep)
  case collector(CollectorRouteStep)
}

enum ProviderRouteAvailability: Equatable, Codable, Sendable {
  case enabled
  case disabled(reason: String)

  var isEnabled: Bool {
    if case .enabled = self { return true }
    return false
  }
}

struct ProviderRoute: Equatable, Codable, Sendable {
  let id: String
  let selector: ProviderRouteSelector
  let priority: Int
  let availability: ProviderRouteAvailability
  let execution: ProviderRouteExecution?
  let sourceKind: UsageSourceKind
  let legacyProviderID: ProviderID?
  let fallbackRouteID: String?
  let fallbackFailureCodes: Set<String>
}

enum ProviderRouteRegistryError: Error, Equatable {
  case duplicateRouteID(String)
  case invalidStableID(String)
  case enabledRouteMissingExecution(String)
  case automaticCollectorSource(String)
  case collectorStepMissingExactIdentity(String)
  case enabledCollectorMissingManifest(String)
  case enabledCollectorPinMismatch(String)
  case duplicateEnabledRoute(CollectionTargetKey)
  case invalidTargetIdentity
  case routeNotFound(CollectionTargetKey)
  case routeDisabled(String)
}

struct ProviderRouteRegistry: Sendable {
  static let pinnedCodexBarCommit = CollectorWireIdentity.codexBarUpstreamPin

  let routes: [ProviderRoute]

  init(routes: [ProviderRoute]) throws {
    var routeIDs = Set<String>()
    for route in routes {
      guard ProviderIdentityValidation.isValid(route.id),
            ProviderIdentityValidation.isValid(
              route.selector.productID.rawValue),
            ProviderIdentityValidation.isValid(
              route.selector.scopeKind.rawValue)
      else {
        throw ProviderRouteRegistryError.invalidStableID(route.id)
      }
      guard routeIDs.insert(route.id).inserted else {
        throw ProviderRouteRegistryError.duplicateRouteID(route.id)
      }
      guard !route.availability.isEnabled || route.execution != nil else {
        throw ProviderRouteRegistryError.enabledRouteMissingExecution(route.id)
      }
      guard case let .collector(step)? = route.execution else { continue }
      guard step.source != .auto else {
        throw ProviderRouteRegistryError.automaticCollectorSource(route.id)
      }
      guard !step.provider.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !step.exactStrategyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw ProviderRouteRegistryError.collectorStepMissingExactIdentity(route.id)
      }
      if route.availability.isEnabled {
        guard let digest = step.manifestDigest, Self.isSHA256(digest) else {
          throw ProviderRouteRegistryError.enabledCollectorMissingManifest(route.id)
        }
        guard step.upstreamPin == Self.pinnedCodexBarCommit else {
          throw ProviderRouteRegistryError.enabledCollectorPinMismatch(route.id)
        }
      }
    }
    self.routes = routes.sorted {
      if $0.priority == $1.priority { return $0.id < $1.id }
      return $0.priority < $1.priority
    }
  }

  func resolve(_ target: CollectionTargetKey) throws -> ProviderRoute {
    guard target.hasValidStableIdentity else {
      throw ProviderRouteRegistryError.invalidTargetIdentity
    }
    let matching = routes.filter {
      $0.selector.matches(target) && $0.availability.isEnabled
    }
    guard let route = matching.first else {
      if let disabled = routes.first(where: { $0.selector.matches(target) }) {
        throw ProviderRouteRegistryError.routeDisabled(disabled.id)
      }
      throw ProviderRouteRegistryError.routeNotFound(target)
    }
    guard matching.count == 1 else {
      throw ProviderRouteRegistryError.duplicateEnabledRoute(target)
    }
    return route
  }

  func resolve(routeID: String, target: CollectionTargetKey) throws -> ProviderRoute {
    guard target.hasValidStableIdentity else {
      throw ProviderRouteRegistryError.invalidTargetIdentity
    }
    guard let route = route(id: routeID),
          route.selector.matches(target)
    else {
      throw ProviderRouteRegistryError.routeNotFound(target)
    }
    guard route.availability.isEnabled else {
      throw ProviderRouteRegistryError.routeDisabled(route.id)
    }
    return route
  }

  func route(id: String) -> ProviderRoute? {
    routes.first { $0.id == id }
  }

  static let production: ProviderRouteRegistry = {
    do {
      return try ProviderRouteRegistry(routes: Self.productionRoutes)
    } catch {
      preconditionFailure("Invalid built-in provider route registry: \(error)")
    }
  }()

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { character in
      ("0"..."9").contains(character) || ("a"..."f").contains(character)
    }
  }

  private static let productionRoutes: [ProviderRoute] = [
    native(
      id: "native.codex.personal",
      product: .codexPersonal,
      accountMode: .ambient,
      scope: "personal",
      adapterID: "dashis.codex.personal",
      sourceKind: .experimentalPrivate,
      legacyProviderID: .codex),
    disabledCollector(
      id: "collector.codex.personal.oauth",
      product: .codexPersonal,
      accountMode: .ambient,
      scope: "personal",
      provider: "codex",
      source: .oauth,
      strategyID: "codex.oauth",
      strategyKind: .oauth,
      sourceKind: .experimentalPrivate,
      fallbackRouteID: "collector.codex.personal.cli",
      fallbackFailureCodes: ["oauth_credentials_repairable"]),
    disabledCollector(
      id: "collector.codex.personal.cli",
      product: .codexPersonal,
      accountMode: .ambient,
      scope: "personal",
      provider: "codex",
      source: .cli,
      strategyID: "codex.cli",
      strategyKind: .cli,
      sourceKind: .officialLocalBridge),
    native(
      id: "native.codex.enterprise",
      product: .codexEnterprise,
      accountMode: .selected,
      scope: "enterprise",
      adapterID: "dashis.codex.enterprise",
      sourceKind: .officialDirect,
      legacyProviderID: .codex),
    native(
      id: "native.claude.local",
      product: .claudeLocal,
      accountMode: .ambient,
      scope: "local",
      adapterID: "dashis.claude.status-line",
      sourceKind: .officialLocalBridge,
      legacyProviderID: .claude),
    disabledCollector(
      id: "collector.claude.oauth",
      product: .claudeOAuth,
      accountMode: .selected,
      scope: "personal",
      provider: "claude",
      source: .oauth,
      strategyID: "claude.oauth",
      strategyKind: .oauth,
      sourceKind: .experimentalPrivate),
    disabledCollector(
      id: "collector.claude.admin",
      product: .claudeAdmin,
      accountMode: .selected,
      scope: "organization",
      provider: "claude",
      source: .api,
      strategyID: "claude.admin-api",
      strategyKind: .apiToken,
      sourceKind: .officialDirect),
    disabledCollector(
      id: "collector.claude.web",
      product: .claudeWeb,
      accountMode: .selected,
      scope: "personal",
      provider: "claude",
      source: .web,
      strategyID: "claude.web",
      strategyKind: .web,
      sourceKind: .experimentalPrivate),
    native(
      id: "native.google.consumer.manual",
      product: .googleConsumerManual,
      accountMode: .ambient,
      scope: "consumer",
      adapterID: "dashis.google.consumer.manual",
      sourceKind: .manualOnly,
      legacyProviderID: .google),
    native(
      id: "native.gemini.project",
      product: .geminiProject,
      accountMode: .selected,
      scope: "project",
      adapterID: "dashis.gemini.project",
      sourceKind: .officialDerived,
      legacyProviderID: .google),
    disabledCollector(
      id: "collector.gemini.cli",
      product: .geminiCLI,
      accountMode: .ambient,
      scope: "cli",
      provider: "gemini",
      source: .api,
      strategyID: "gemini.api",
      strategyKind: .apiToken,
      sourceKind: .experimentalPrivate),
    disabledCollector(
      id: "collector.vertex.project",
      product: .vertexProject,
      accountMode: .selected,
      scope: "project",
      provider: "vertexai",
      source: .oauth,
      strategyID: "vertexai.oauth",
      strategyKind: .oauth,
      sourceKind: .experimentalPrivate),
    native(
      id: "native.openrouter.account",
      product: .openRouterAccount,
      accountMode: .selected,
      scope: "account",
      adapterID: "dashis.openrouter.account",
      sourceKind: .officialDirect,
      legacyProviderID: .openRouter),
    native(
      id: "native.openrouter.key",
      product: .openRouterKey,
      accountMode: .selected,
      scope: "key",
      adapterID: "dashis.openrouter.key",
      sourceKind: .officialDirect,
      legacyProviderID: .openRouter),
    disabledCollector(
      id: "collector.openrouter.api",
      product: .openRouterKey,
      accountMode: .selected,
      scope: "key",
      provider: "openrouter",
      source: .api,
      strategyID: "openrouter.api",
      strategyKind: .apiToken,
      sourceKind: .officialDirect),
  ] + CollectorLiveRouteCatalog.routes.map(Self.liveCollector)

  private static func native(
    id: String,
    product: ProviderProductID,
    accountMode: ProviderRouteAccountMode,
    scope: ProviderScopeID,
    adapterID: String,
    sourceKind: UsageSourceKind,
    legacyProviderID: ProviderID
  ) -> ProviderRoute {
    ProviderRoute(
      id: id,
      selector: ProviderRouteSelector(
        productID: product,
        accountMode: accountMode,
        scopeKind: ProviderRouteScopeKind(rawValue: scope.rawValue)),
      priority: 100,
      availability: .enabled,
      execution: .native(NativeRouteStep(adapterID: adapterID)),
      sourceKind: sourceKind,
      legacyProviderID: legacyProviderID,
      fallbackRouteID: nil,
      fallbackFailureCodes: [])
  }

  private static func disabledCollector(
    id: String,
    product: ProviderProductID,
    accountMode: ProviderRouteAccountMode,
    scope: ProviderScopeID,
    provider: CollectorProviderID,
    source: CollectorSourceMode,
    strategyID: String,
    strategyKind: CollectorStrategyKind,
    sourceKind: UsageSourceKind,
    fallbackRouteID: String? = nil,
    fallbackFailureCodes: Set<String> = []
  ) -> ProviderRoute {
    ProviderRoute(
      id: id,
      selector: ProviderRouteSelector(
        productID: product,
        accountMode: accountMode,
        scopeKind: ProviderRouteScopeKind(rawValue: scope.rawValue)),
      priority: 200,
      availability: .disabled(
        reason: "No reviewed effect manifest and brokered host-services path exists."),
      execution: .collector(CollectorRouteStep(
        provider: provider,
        source: source,
        exactStrategyID: strategyID,
        exactStrategyKind: strategyKind,
        includeCredits: false,
        includeOptionalUsage: false,
        interaction: .userInitiated,
        manifestDigest: nil,
        upstreamPin: Self.pinnedCodexBarCommit)),
      sourceKind: sourceKind,
      legacyProviderID: nil,
      fallbackRouteID: fallbackRouteID,
      fallbackFailureCodes: fallbackFailureCodes)
  }

  private static func liveCollector(
    _ definition: CollectorLiveRouteDefinition
  ) -> ProviderRoute {
    ProviderRoute(
      id: definition.id,
      selector: ProviderRouteSelector(
        productID: ProviderProductID(
          rawValue: "collector.\(definition.provider.rawValue)"),
        accountMode: .ambient,
        scopeKind: "usage"),
      priority: 300,
      availability: .enabled,
      execution: .collector(CollectorRouteStep(
        provider: definition.provider,
        source: definition.source,
        exactStrategyID: definition.strategyID,
        exactStrategyKind: definition.strategyKind,
        includeCredits: definition.includeCredits,
        includeOptionalUsage: definition.includeOptionalUsage,
        interaction: definition.interaction,
        manifestDigest: Self.sha256(definition.manifestMaterial),
        upstreamPin: definition.upstreamPin)),
      sourceKind: .experimentalPrivate,
      legacyProviderID: ProviderID(rawValue: definition.provider.rawValue),
      fallbackRouteID: nil,
      fallbackFailureCodes: [])
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
