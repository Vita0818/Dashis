import Foundation

public struct CollectorProviderID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public enum CollectorSourceMode: String, CaseIterable, Codable, Sendable {
    case auto
    case web
    case cli
    case oauth
    case api
}

public enum CollectorRuntime: String, Codable, Sendable {
    case app
    case cli
}

public enum CollectorInteraction: String, Codable, Sendable {
    case background
    case userInitiated
}

public struct CollectorAccountSelection: Codable, Equatable, Sendable {
    public let id: UUID?
    public let label: String?

    public static let ambient = CollectorAccountSelection()

    public var isAmbient: Bool {
        self.id == nil && self.label == nil
    }

    public init(id: UUID? = nil, label: String? = nil) {
        self.id = id
        self.label = label
    }
}

public struct CollectorRequest: Codable, Equatable, Sendable {
    public let provider: CollectorProviderID
    public let account: CollectorAccountSelection
    public let source: CollectorSourceMode
    public let includeCredits: Bool
    public let includeOptionalUsage: Bool
    public let interaction: CollectorInteraction

    public init(
        provider: CollectorProviderID,
        account: CollectorAccountSelection = .ambient,
        source: CollectorSourceMode,
        includeCredits: Bool = false,
        includeOptionalUsage: Bool = false,
        interaction: CollectorInteraction = .userInitiated)
    {
        self.provider = provider
        self.account = account
        self.source = source
        self.includeCredits = includeCredits
        self.includeOptionalUsage = includeOptionalUsage
        self.interaction = interaction
    }
}

public struct CollectorProvider: Codable, Equatable, Sendable {
    public let id: CollectorProviderID
    public let displayName: String
    public let supportedSources: [CollectorSourceMode]
    public let supportsCredits: Bool
    public let primaryWindowLabel: String
    public let secondaryWindowLabel: String
    public let tertiaryWindowLabel: String?
    public let dashboardURL: URL?

    public init(
        id: CollectorProviderID,
        displayName: String,
        supportedSources: [CollectorSourceMode],
        supportsCredits: Bool,
        primaryWindowLabel: String,
        secondaryWindowLabel: String,
        tertiaryWindowLabel: String?,
        dashboardURL: URL?)
    {
        self.id = id
        self.displayName = displayName
        self.supportedSources = supportedSources
        self.supportsCredits = supportsCredits
        self.primaryWindowLabel = primaryWindowLabel
        self.secondaryWindowLabel = secondaryWindowLabel
        self.tertiaryWindowLabel = tertiaryWindowLabel
        self.dashboardURL = dashboardURL
    }
}
