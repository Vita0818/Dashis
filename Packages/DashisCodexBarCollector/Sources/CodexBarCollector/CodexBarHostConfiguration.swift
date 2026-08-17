import CodexBarCore
import DashisCollectorContract
import Foundation

public enum CodexBarAccountIdentityValidation: String, Sendable {
    case verified
    case insufficientEvidence
    case mismatch
}

/// Host-owned, provider-reported identity fields that must match before a
/// selected-account result can be attributed to that account.
///
/// `accountEmail` or `providerAccountID` must be non-empty. Organization and
/// login method are optional additional constraints, not identity anchors.
public struct CodexBarAccountIdentityExpectation: Sendable {
    public let provider: CollectorProviderID
    public let accountEmail: String?
    public let accountOrganization: String?
    public let loginMethod: String?
    public let providerAccountID: String?

    public init(
        provider: CollectorProviderID,
        accountEmail: String? = nil,
        accountOrganization: String? = nil,
        loginMethod: String? = nil,
        providerAccountID: String? = nil)
    {
        self.provider = provider
        self.accountEmail = accountEmail
        self.accountOrganization = accountOrganization
        self.loginMethod = loginMethod
        self.providerAccountID = providerAccountID
    }

    public var hasStableAnchor: Bool {
        Self.nonEmpty(self.accountEmail) != nil || Self.nonEmpty(self.providerAccountID) != nil
    }

    /// Validates usage identity plus any additional account-bearing email
    /// returned in the same result bundle (currently the OpenAI dashboard).
    public func validate(
        _ identity: CollectorIdentity?,
        additionalAccountEmail: String? = nil) -> CodexBarAccountIdentityValidation
    {
        guard self.hasStableAnchor, let identity else {
            return .insufficientEvidence
        }
        guard let reportedProvider = identity.providerID else {
            return .insufficientEvidence
        }
        guard reportedProvider == self.provider else {
            return .mismatch
        }

        if let expectedEmail = Self.normalizedEmail(self.accountEmail) {
            guard let actualEmail = Self.normalizedEmail(identity.accountEmail) else {
                return .insufficientEvidence
            }
            guard actualEmail == expectedEmail else {
                return .mismatch
            }
        }
        if let expectedOrganization = Self.nonEmpty(self.accountOrganization) {
            guard let actualOrganization = Self.nonEmpty(identity.accountOrganization) else {
                return .insufficientEvidence
            }
            guard actualOrganization == expectedOrganization else {
                return .mismatch
            }
        }
        if let expectedLoginMethod = Self.nonEmpty(self.loginMethod) {
            guard let actualLoginMethod = Self.nonEmpty(identity.loginMethod) else {
                return .insufficientEvidence
            }
            guard actualLoginMethod == expectedLoginMethod else {
                return .mismatch
            }
        }
        if let expectedProviderAccountID = Self.nonEmpty(self.providerAccountID) {
            guard let actualProviderAccountID = Self.nonEmpty(identity.accountID) else {
                return .insufficientEvidence
            }
            guard actualProviderAccountID == expectedProviderAccountID else {
                return .mismatch
            }
        }

        if let additionalEmail = Self.normalizedEmail(additionalAccountEmail) {
            let comparisonEmail =
                Self.normalizedEmail(self.accountEmail)
                    ?? Self.normalizedEmail(identity.accountEmail)
            guard let comparisonEmail else {
                return .insufficientEvidence
            }
            guard additionalEmail == comparisonEmail else {
                return .mismatch
            }
        }
        return .verified
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        self.nonEmpty(value)?.lowercased()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

public struct CodexBarResolvedAccountContext: Sendable {
    public let confirmedAccountID: UUID
    /// Complete environment for this selected account. The environment and
    /// optional settings replace, rather than merge with, ambient host values
    /// so stale credentials cannot bleed across accounts.
    public let environment: [String: String]
    public let settings: ProviderSettingsSnapshot?
    public let selectedTokenAccountID: UUID?
    public let identityExpectation: CodexBarAccountIdentityExpectation

    public init(
        confirmedAccountID: UUID,
        environment: [String: String],
        settings: ProviderSettingsSnapshot? = nil,
        selectedTokenAccountID: UUID? = nil,
        identityExpectation: CodexBarAccountIdentityExpectation)
    {
        self.confirmedAccountID = confirmedAccountID
        self.environment = environment
        self.settings = settings
        self.selectedTokenAccountID = selectedTokenAccountID
        self.identityExpectation = identityExpectation
    }
}

/// Explicit host-owned settings and persistence hooks for advanced provider
/// configuration. The default value installs no settings or write callbacks.
public struct CodexBarHostConfiguration: Sendable {
    public typealias AccountResolver =
        @Sendable (CollectorProviderID, CollectorAccountSelection) async throws
            -> CodexBarResolvedAccountContext
    public typealias TokenAccountTokenUpdater =
        @Sendable (CollectorProviderID, UUID, String) async -> Void
    public typealias ProviderManualTokenUpdater =
        @Sendable (CollectorProviderID, String) async -> Void

    public static let disabled = CodexBarHostConfiguration()

    public let settings: ProviderSettingsSnapshot?
    public let accountResolver: AccountResolver?
    public let tokenAccountTokenUpdater: TokenAccountTokenUpdater?
    public let providerManualTokenUpdater: ProviderManualTokenUpdater?

    public init(
        settings: ProviderSettingsSnapshot? = nil,
        accountResolver: AccountResolver? = nil,
        tokenAccountTokenUpdater: TokenAccountTokenUpdater? = nil,
        providerManualTokenUpdater: ProviderManualTokenUpdater? = nil)
    {
        self.settings = settings
        self.accountResolver = accountResolver
        self.tokenAccountTokenUpdater = tokenAccountTokenUpdater
        self.providerManualTokenUpdater = providerManualTokenUpdater
    }
}
