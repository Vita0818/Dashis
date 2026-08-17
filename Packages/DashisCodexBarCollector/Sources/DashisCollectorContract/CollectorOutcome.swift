import Foundation

public enum CollectorStrategyKind: String, Codable, Sendable {
    case cli
    case web
    case oauth
    case apiToken
    case localProbe
    case webDashboard
}

public enum CollectorAttemptDisposition: String, Codable, Sendable {
    case policyDenied
    case unavailable
    case failed
    case identityRejected
    case succeeded
    case cancelled
}

public struct CollectorFailure: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct CollectorAttempt: Codable, Equatable, Sendable {
    public let index: Int
    public let strategyID: String
    public let kind: CollectorStrategyKind
    public let disposition: CollectorAttemptDisposition
    public let policyRuleID: String?
    public let fallbackAllowed: Bool?
    public let failure: CollectorFailure?

    public init(
        index: Int,
        strategyID: String,
        kind: CollectorStrategyKind,
        disposition: CollectorAttemptDisposition,
        policyRuleID: String? = nil,
        fallbackAllowed: Bool? = nil,
        failure: CollectorFailure? = nil)
    {
        self.index = index
        self.strategyID = strategyID
        self.kind = kind
        self.disposition = disposition
        self.policyRuleID = policyRuleID
        self.fallbackAllowed = fallbackAllowed
        self.failure = failure
    }
}

public struct CollectorResolvedSource: Codable, Equatable, Sendable {
    public let label: String
    public let strategyID: String
    public let kind: CollectorStrategyKind

    public init(label: String, strategyID: String, kind: CollectorStrategyKind) {
        self.label = label
        self.strategyID = strategyID
        self.kind = kind
    }
}

public enum CollectorAccountResolutionKind: String, Codable, Sendable {
    case unresolved
    case ambient
    case hostResolved
    case resultVerified
}

public struct CollectorAccountResolution: Codable, Equatable, Sendable {
    public let kind: CollectorAccountResolutionKind
    public let confirmedAccountID: UUID?

    public init(kind: CollectorAccountResolutionKind, confirmedAccountID: UUID? = nil) {
        self.kind = kind
        self.confirmedAccountID = confirmedAccountID
    }
}

public enum CollectorDiagnosticSeverity: String, Codable, Sendable {
    case warning
}

public struct CollectorDiagnostic: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let severity: CollectorDiagnosticSeverity

    public init(
        code: String,
        message: String,
        severity: CollectorDiagnosticSeverity = .warning)
    {
        self.code = code
        self.message = message
        self.severity = severity
    }
}

public struct CollectorProviderArtifact: Codable, Equatable, Sendable {
    public let schemaID: String
    public let observedAt: Date
    public let payload: CollectorValue

    public init(schemaID: String, observedAt: Date, payload: CollectorValue) {
        self.schemaID = schemaID
        self.observedAt = observedAt
        self.payload = payload
    }
}

public enum CollectorCredentialComparison: String, Codable, Sendable {
    case matched
    case mismatch
    case absent
    case unavailable
    case notApplicable
    case notObserved
}

public struct CollectorCredentialOwnership: Codable, Equatable, Sendable {
    public let historyOwnerIdentifier: String?
    public let comparison: CollectorCredentialComparison

    public init(
        historyOwnerIdentifier: String?,
        comparison: CollectorCredentialComparison)
    {
        self.historyOwnerIdentifier = historyOwnerIdentifier
        self.comparison = comparison
    }
}

public enum CollectorWindowRole: String, Codable, Sendable {
    case primary
    case secondary
    case tertiary
    case extra
}

public struct CollectorWindow: Codable, Equatable, Sendable {
    public let role: CollectorWindowRole
    public let id: String
    public let title: String?
    public let usedPercent: Double
    public let remainingPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?
    public let nextRegenPercent: Double?
    public let isSyntheticPlaceholder: Bool
    public let usageKnown: Bool

    public init(
        role: CollectorWindowRole,
        id: String,
        title: String?,
        usedPercent: Double,
        remainingPercent: Double,
        windowMinutes: Int?,
        resetsAt: Date?,
        resetDescription: String?,
        nextRegenPercent: Double?,
        isSyntheticPlaceholder: Bool,
        usageKnown: Bool)
    {
        self.role = role
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
        self.nextRegenPercent = nextRegenPercent
        self.isSyntheticPlaceholder = isSyntheticPlaceholder
        self.usageKnown = usageKnown
    }
}

public struct CollectorIdentity: Codable, Equatable, Sendable {
    public let providerID: CollectorProviderID?
    public let accountEmail: String?
    public let accountOrganization: String?
    public let loginMethod: String?
    public let accountID: String?

    public init(
        providerID: CollectorProviderID?,
        accountEmail: String?,
        accountOrganization: String?,
        loginMethod: String?,
        accountID: String?)
    {
        self.providerID = providerID
        self.accountEmail = accountEmail
        self.accountOrganization = accountOrganization
        self.loginMethod = loginMethod
        self.accountID = accountID
    }
}

public enum CollectorDataConfidence: String, Codable, Sendable {
    case exact
    case estimated
    case percentOnly
    case unknown
}

public struct CollectorCost: Codable, Equatable, Sendable {
    public let used: Double
    public let limit: Double
    public let currencyCode: String
    public let period: String?
    public let resetsAt: Date?
    public let nextRegenAmount: Double?
    public let personalUsed: Double?
    public let observedAt: Date

    public init(
        used: Double,
        limit: Double,
        currencyCode: String,
        period: String?,
        resetsAt: Date?,
        nextRegenAmount: Double?,
        personalUsed: Double?,
        observedAt: Date)
    {
        self.used = used
        self.limit = limit
        self.currencyCode = currencyCode
        self.period = period
        self.resetsAt = resetsAt
        self.nextRegenAmount = nextRegenAmount
        self.personalUsed = personalUsed
        self.observedAt = observedAt
    }
}

public struct CollectorUsage: Codable, Equatable, Sendable {
    public let observedAt: Date
    public let confidence: CollectorDataConfidence
    public let identity: CollectorIdentity?
    public let windows: [CollectorWindow]
    public let cost: CollectorCost?
    public let subscriptionExpiresAt: Date?
    public let subscriptionRenewsAt: Date?
    public let extensions: [String: CollectorValue]

    public init(
        observedAt: Date,
        confidence: CollectorDataConfidence,
        identity: CollectorIdentity?,
        windows: [CollectorWindow],
        cost: CollectorCost?,
        subscriptionExpiresAt: Date?,
        subscriptionRenewsAt: Date?,
        extensions: [String: CollectorValue])
    {
        self.observedAt = observedAt
        self.confidence = confidence
        self.identity = identity
        self.windows = windows
        self.cost = cost
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.subscriptionRenewsAt = subscriptionRenewsAt
        self.extensions = extensions
    }
}

public struct CollectorCreditEvent: Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let service: String
    public let creditsUsed: Double

    public init(id: UUID, date: Date, service: String, creditsUsed: Double) {
        self.id = id
        self.date = date
        self.service = service
        self.creditsUsed = creditsUsed
    }
}

public struct CollectorCreditLimit: Codable, Equatable, Sendable {
    public let title: String
    public let used: Double
    public let limit: Double
    public let remaining: Double
    public let remainingPercent: Double
    public let resetsAt: Date?
    public let observedAt: Date

    public init(
        title: String,
        used: Double,
        limit: Double,
        remaining: Double,
        remainingPercent: Double,
        resetsAt: Date?,
        observedAt: Date)
    {
        self.title = title
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
    }
}

public struct CollectorCredits: Codable, Equatable, Sendable {
    public let remaining: Double?
    public let events: [CollectorCreditEvent]
    public let observedAt: Date
    public let limit: CollectorCreditLimit?

    public init(
        remaining: Double?,
        events: [CollectorCreditEvent],
        observedAt: Date,
        limit: CollectorCreditLimit?)
    {
        self.remaining = remaining
        self.events = events
        self.observedAt = observedAt
        self.limit = limit
    }
}

public struct CollectorFreshness: Codable, Equatable, Sendable {
    public let collectedAt: Date
    public let usageObservedAt: Date?
    public let creditsObservedAt: Date?
    public let costObservedAt: Date?
    public let conservativeObservedAt: Date?

    public init(
        collectedAt: Date,
        usageObservedAt: Date?,
        creditsObservedAt: Date?,
        costObservedAt: Date?)
    {
        self.collectedAt = collectedAt
        self.usageObservedAt = usageObservedAt
        self.creditsObservedAt = creditsObservedAt
        self.costObservedAt = costObservedAt
        self.conservativeObservedAt = [
            usageObservedAt,
            creditsObservedAt,
            costObservedAt,
        ].compactMap(\.self).min()
    }
}

public struct CollectorOutcome: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let provider: CollectorProviderID
    public let account: CollectorAccountSelection
    public let accountResolution: CollectorAccountResolution
    public let requestedSource: CollectorSourceMode
    public let resolvedSource: CollectorResolvedSource?
    public let startedAt: Date
    public let finishedAt: Date
    public let attempts: [CollectorAttempt]
    public let usage: CollectorUsage?
    public let credits: CollectorCredits?
    public let artifacts: [CollectorProviderArtifact]
    public let diagnostics: [CollectorDiagnostic]
    public let credentialOwnership: CollectorCredentialOwnership?
    public let freshness: CollectorFreshness
    public let failure: CollectorFailure?

    public init(
        schemaVersion: Int = CollectorOutcome.currentSchemaVersion,
        provider: CollectorProviderID,
        account: CollectorAccountSelection,
        accountResolution: CollectorAccountResolution,
        requestedSource: CollectorSourceMode,
        resolvedSource: CollectorResolvedSource?,
        startedAt: Date,
        finishedAt: Date,
        attempts: [CollectorAttempt],
        usage: CollectorUsage?,
        credits: CollectorCredits?,
        artifacts: [CollectorProviderArtifact],
        diagnostics: [CollectorDiagnostic],
        credentialOwnership: CollectorCredentialOwnership?,
        freshness: CollectorFreshness,
        failure: CollectorFailure?)
    {
        self.schemaVersion = schemaVersion
        self.provider = provider
        self.account = account
        self.accountResolution = accountResolution
        self.requestedSource = requestedSource
        self.resolvedSource = resolvedSource
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.attempts = attempts
        self.usage = usage
        self.credits = credits
        self.artifacts = artifacts
        self.diagnostics = diagnostics
        self.credentialOwnership = credentialOwnership
        self.freshness = freshness
        self.failure = failure
    }
}
