import Foundation

public enum CollectorCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case strategyResolution
    case opaqueUpstreamExecution
    case network
    case providerLocalState
    case browserSession
    case keychain
    case subprocess
    case credentialMutation
    case potentiallyBillableProbe
}

public enum CollectorAccountScope: Equatable, Sendable {
    case ambient
    case selected(UUID)

    func matches(_ account: CollectorAccountSelection) -> Bool {
        switch self {
        case .ambient:
            account.isAmbient
        case let .selected(id):
            account.id == id
        }
    }
}

public struct CollectorPolicyRequest: Equatable, Sendable {
    public let provider: CollectorProviderID
    public let account: CollectorAccountSelection
    public let requestedSource: CollectorSourceMode
    public let runtime: CollectorRuntime
    public let includeCredits: Bool
    public let includeOptionalUsage: Bool
    public let interaction: CollectorInteraction

    public init(
        provider: CollectorProviderID,
        account: CollectorAccountSelection,
        requestedSource: CollectorSourceMode,
        runtime: CollectorRuntime,
        includeCredits: Bool,
        includeOptionalUsage: Bool,
        interaction: CollectorInteraction)
    {
        self.provider = provider
        self.account = account
        self.requestedSource = requestedSource
        self.runtime = runtime
        self.includeCredits = includeCredits
        self.includeOptionalUsage = includeOptionalUsage
        self.interaction = interaction
    }
}

public struct CollectorPlanningCandidate: Equatable, Sendable {
    public let request: CollectorPolicyRequest
    public let requiredCapabilities: Set<CollectorCapability>

    public init(
        request: CollectorPolicyRequest,
        requiredCapabilities: Set<CollectorCapability>)
    {
        self.request = request
        self.requiredCapabilities = requiredCapabilities
    }
}

public struct CollectorSourceCandidate: Equatable, Sendable {
    public let request: CollectorPolicyRequest
    public let strategyID: String
    public let kind: CollectorStrategyKind
    public let requiredCapabilities: Set<CollectorCapability>

    public init(
        request: CollectorPolicyRequest,
        strategyID: String,
        kind: CollectorStrategyKind,
        requiredCapabilities: Set<CollectorCapability>)
    {
        self.request = request
        self.strategyID = strategyID
        self.kind = kind
        self.requiredCapabilities = requiredCapabilities
    }
}

public struct CollectorPolicyDecision: Equatable, Sendable {
    public let allowed: Bool
    public let ruleID: String
    public let reason: String

    public init(allowed: Bool, ruleID: String, reason: String) {
        self.allowed = allowed
        self.ruleID = ruleID
        self.reason = reason
    }

    public static func allow(ruleID: String, reason: String) -> CollectorPolicyDecision {
        CollectorPolicyDecision(allowed: true, ruleID: ruleID, reason: reason)
    }

    public static func deny(ruleID: String, reason: String) -> CollectorPolicyDecision {
        CollectorPolicyDecision(allowed: false, ruleID: ruleID, reason: reason)
    }
}

public protocol CollectorSourcePolicy: Sendable {
    func evaluateRequest(_ request: CollectorPolicyRequest) -> CollectorPolicyDecision
    func evaluatePlanning(_ candidate: CollectorPlanningCandidate) -> CollectorPolicyDecision
    func evaluateStrategy(_ candidate: CollectorSourceCandidate) -> CollectorPolicyDecision
}

public struct CollectorRequestRule: Equatable, Sendable {
    public let id: String
    public let provider: CollectorProviderID
    public let account: CollectorAccountScope
    public let source: CollectorSourceMode
    public let runtime: CollectorRuntime
    public let includeCredits: Bool
    public let includeOptionalUsage: Bool
    public let interaction: CollectorInteraction
    public let allow: Bool
    public let reason: String

    public init(
        id: String,
        provider: CollectorProviderID,
        account: CollectorAccountScope,
        source: CollectorSourceMode,
        runtime: CollectorRuntime,
        includeCredits: Bool,
        includeOptionalUsage: Bool,
        interaction: CollectorInteraction,
        allow: Bool,
        reason: String)
    {
        self.id = id
        self.provider = provider
        self.account = account
        self.source = source
        self.runtime = runtime
        self.includeCredits = includeCredits
        self.includeOptionalUsage = includeOptionalUsage
        self.interaction = interaction
        self.allow = allow
        self.reason = reason
    }

    func matches(_ request: CollectorPolicyRequest) -> Bool {
        self.provider == request.provider
            && self.account.matches(request.account)
            && self.source == request.requestedSource
            && self.runtime == request.runtime
            && self.includeCredits == request.includeCredits
            && self.includeOptionalUsage == request.includeOptionalUsage
            && self.interaction == request.interaction
    }
}

public struct CollectorPlanningRule: Equatable, Sendable {
    public let id: String
    public let provider: CollectorProviderID
    public let account: CollectorAccountScope
    public let source: CollectorSourceMode
    public let runtime: CollectorRuntime
    public let includeCredits: Bool
    public let includeOptionalUsage: Bool
    public let interaction: CollectorInteraction
    public let allow: Bool
    public let reason: String

    public init(
        id: String,
        provider: CollectorProviderID,
        account: CollectorAccountScope,
        source: CollectorSourceMode,
        runtime: CollectorRuntime,
        includeCredits: Bool,
        includeOptionalUsage: Bool,
        interaction: CollectorInteraction,
        allow: Bool,
        reason: String)
    {
        self.id = id
        self.provider = provider
        self.account = account
        self.source = source
        self.runtime = runtime
        self.includeCredits = includeCredits
        self.includeOptionalUsage = includeOptionalUsage
        self.interaction = interaction
        self.allow = allow
        self.reason = reason
    }

    func matches(_ candidate: CollectorPlanningCandidate) -> Bool {
        let request = candidate.request
        return self.provider == request.provider
            && self.account.matches(request.account)
            && self.source == request.requestedSource
            && self.runtime == request.runtime
            && self.includeCredits == request.includeCredits
            && self.includeOptionalUsage == request.includeOptionalUsage
            && self.interaction == request.interaction
    }
}

public struct CollectorStrategyRule: Equatable, Sendable {
    public let id: String
    public let provider: CollectorProviderID
    public let account: CollectorAccountScope
    public let source: CollectorSourceMode
    public let runtime: CollectorRuntime
    public let includeCredits: Bool
    public let includeOptionalUsage: Bool
    public let interaction: CollectorInteraction
    public let strategyID: String
    public let kind: CollectorStrategyKind
    public let allow: Bool
    public let reason: String

    public init(
        id: String,
        provider: CollectorProviderID,
        account: CollectorAccountScope,
        source: CollectorSourceMode,
        runtime: CollectorRuntime,
        includeCredits: Bool,
        includeOptionalUsage: Bool,
        interaction: CollectorInteraction,
        strategyID: String,
        kind: CollectorStrategyKind,
        allow: Bool,
        reason: String)
    {
        self.id = id
        self.provider = provider
        self.account = account
        self.source = source
        self.runtime = runtime
        self.includeCredits = includeCredits
        self.includeOptionalUsage = includeOptionalUsage
        self.interaction = interaction
        self.strategyID = strategyID
        self.kind = kind
        self.allow = allow
        self.reason = reason
    }

    func matches(_ candidate: CollectorSourceCandidate) -> Bool {
        let request = candidate.request
        return self.provider == request.provider
            && self.account.matches(request.account)
            && self.source == request.requestedSource
            && self.runtime == request.runtime
            && self.includeCredits == request.includeCredits
            && self.includeOptionalUsage == request.includeOptionalUsage
            && self.interaction == request.interaction
            && self.strategyID == candidate.strategyID
            && self.kind == candidate.kind
    }
}

public struct StaticCollectorSourcePolicy: CollectorSourcePolicy, Sendable {
    public let allowedCapabilities: Set<CollectorCapability>
    public let requestRules: [CollectorRequestRule]
    public let planningRules: [CollectorPlanningRule]
    public let strategyRules: [CollectorStrategyRule]
    public let defaultRequestDecision: CollectorPolicyDecision
    public let defaultPlanningDecision: CollectorPolicyDecision
    public let defaultStrategyDecision: CollectorPolicyDecision

    public static let denyAll = StaticCollectorSourcePolicy()

    public init(
        allowedCapabilities: Set<CollectorCapability> = [],
        requestRules: [CollectorRequestRule] = [],
        planningRules: [CollectorPlanningRule] = [],
        strategyRules: [CollectorStrategyRule] = [],
        defaultRequestDecision: CollectorPolicyDecision = .deny(
            ruleID: "default-deny-request",
            reason: "No exact collection request has been explicitly allowed."),
        defaultPlanningDecision: CollectorPolicyDecision = .deny(
            ruleID: "default-deny-planning",
            reason: "CodexBar strategy resolution has not been explicitly allowed."),
        defaultStrategyDecision: CollectorPolicyDecision = .deny(
            ruleID: "default-deny-strategy",
            reason: "No exact CodexBar strategy has been explicitly allowed."))
    {
        self.allowedCapabilities = allowedCapabilities
        self.requestRules = requestRules
        self.planningRules = planningRules
        self.strategyRules = strategyRules
        self.defaultRequestDecision = defaultRequestDecision
        self.defaultPlanningDecision = defaultPlanningDecision
        self.defaultStrategyDecision = defaultStrategyDecision
    }

    public func evaluateRequest(_ request: CollectorPolicyRequest) -> CollectorPolicyDecision {
        guard let rule = self.requestRules.first(where: { $0.matches(request) }) else {
            return self.defaultRequestDecision
        }
        return CollectorPolicyDecision(allowed: rule.allow, ruleID: rule.id, reason: rule.reason)
    }

    public func evaluatePlanning(_ candidate: CollectorPlanningCandidate) -> CollectorPolicyDecision {
        if let denial = self.capabilityDenial(candidate.requiredCapabilities, phase: "planning") {
            return denial
        }
        guard let rule = self.planningRules.first(where: { $0.matches(candidate) }) else {
            return self.defaultPlanningDecision
        }
        return CollectorPolicyDecision(allowed: rule.allow, ruleID: rule.id, reason: rule.reason)
    }

    public func evaluateStrategy(_ candidate: CollectorSourceCandidate) -> CollectorPolicyDecision {
        if let denial = self.capabilityDenial(candidate.requiredCapabilities, phase: "strategy") {
            return denial
        }
        guard let rule = self.strategyRules.first(where: { $0.matches(candidate) }) else {
            return self.defaultStrategyDecision
        }
        return CollectorPolicyDecision(allowed: rule.allow, ruleID: rule.id, reason: rule.reason)
    }

    private func capabilityDenial(
        _ required: Set<CollectorCapability>,
        phase: String) -> CollectorPolicyDecision?
    {
        let missingCapabilities = required.subtracting(self.allowedCapabilities)
        guard !missingCapabilities.isEmpty else { return nil }
        let names = missingCapabilities.map(\.rawValue).sorted().joined(separator: ", ")
        return .deny(
            ruleID: "capability-deny-\(phase)",
            reason: "The host has not allowed required capabilities: \(names).")
    }
}
