import Foundation

enum ProviderIdentityValidation {
  static func isValid(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.count <= 256
      && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && !value.unicodeScalars.contains(
        where: CharacterSet.controlCharacters.contains)
  }
}

struct ProviderProductID: RawRepresentable, Hashable, Codable, Sendable,
  ExpressibleByStringLiteral
{
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  static let codexPersonal: ProviderProductID = "codex.personal"
  static let codexEnterprise: ProviderProductID = "codex.enterprise"
  static let claudeLocal: ProviderProductID = "claude.local"
  static let claudeOAuth: ProviderProductID = "claude.oauth"
  static let claudeAdmin: ProviderProductID = "claude.admin"
  static let claudeWeb: ProviderProductID = "claude.web"
  static let googleConsumerManual: ProviderProductID = "google.consumer.manual"
  static let geminiProject: ProviderProductID = "gemini.project"
  static let geminiCLI: ProviderProductID = "gemini.cli"
  static let vertexProject: ProviderProductID = "vertex.project"
  static let openRouterAccount: ProviderProductID = "openrouter.account"
  static let openRouterKey: ProviderProductID = "openrouter.key"
}

struct ProviderScopeID: RawRepresentable, Hashable, Codable, Sendable,
  ExpressibleByStringLiteral
{
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

struct ProviderRouteScopeKind: RawRepresentable, Hashable, Codable, Sendable,
  ExpressibleByStringLiteral
{
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

enum ProviderAccountSlot: Hashable, Codable, Sendable {
  case ambient(String)
  case selected(UUID)

  var mode: ProviderRouteAccountMode {
    switch self {
    case .ambient:
      return .ambient
    case .selected:
      return .selected
    }
  }

  var selectedAccountID: UUID? {
    guard case let .selected(id) = self else { return nil }
    return id
  }
}

struct CollectionTargetKey: Hashable, Codable, Sendable {
  let productID: ProviderProductID
  let accountSlot: ProviderAccountSlot
  let scopeKind: ProviderRouteScopeKind
  let scopeID: ProviderScopeID

  init(
    productID: ProviderProductID,
    accountSlot: ProviderAccountSlot,
    scopeKind: ProviderRouteScopeKind,
    scopeID: ProviderScopeID
  ) {
    self.productID = productID
    self.accountSlot = accountSlot
    self.scopeKind = scopeKind
    self.scopeID = scopeID
  }

  var hasValidStableIdentity: Bool {
    guard ProviderIdentityValidation.isValid(productID.rawValue),
          ProviderIdentityValidation.isValid(scopeKind.rawValue),
          ProviderIdentityValidation.isValid(scopeID.rawValue)
    else {
      return false
    }
    if case let .ambient(slot) = accountSlot {
      return ProviderIdentityValidation.isValid(slot)
    }
    return true
  }
}

struct ProviderRunIdentity: Hashable, Codable, Sendable {
  let runID: UUID
  let generation: Int
  let startedAt: Date

  init(runID: UUID = UUID(), generation: Int, startedAt: Date = Date()) {
    self.runID = runID
    self.generation = generation
    self.startedAt = startedAt
  }
}
