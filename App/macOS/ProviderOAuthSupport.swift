import CryptoKit
import Foundation
import Security

struct GoogleDesktopOAuthFlow: Sendable {
  let authorizationURL: URL
  let redirectURI: URL
  let state: String
  let codeVerifier: String
}

struct GoogleSessionAccessToken: Sendable {
  let value: String
  let expiresAt: Date
  let grantedScope: String?

  func isUsable(at date: Date = Date(), leeway: TimeInterval = 30) -> Bool {
    !value.isEmpty
      && value.count <= 8_192
      && !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
      && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
      && expiresAt.timeIntervalSince(date) > leeway
  }
}

enum GoogleDesktopOAuthError: LocalizedError, Equatable {
  case invalidClientID
  case invalidLoopbackRedirect
  case randomGenerationFailed
  case invalidAuthorizationURL
  case invalidCallback
  case stateMismatch
  case authorizationDenied
  case missingAuthorizationCode
  case invalidTokenResponse

  var errorDescription: String? {
    switch self {
    case .invalidClientID:
      "Enter a Google Desktop OAuth client ID."
    case .invalidLoopbackRedirect:
      "The Google OAuth loopback callback is invalid."
    case .randomGenerationFailed:
      "A secure OAuth verifier could not be generated."
    case .invalidAuthorizationURL:
      "The Google authorization URL could not be created."
    case .invalidCallback:
      "Google returned an invalid OAuth callback."
    case .stateMismatch:
      "The Google OAuth state did not match."
    case .authorizationDenied:
      "Google authorization was cancelled or denied."
    case .missingAuthorizationCode:
      "Google did not return an authorization code."
    case .invalidTokenResponse:
      "Google returned an unsupported token response."
    }
  }
}

enum GoogleDesktopOAuth {
  static let cloudPlatformScope = "https://www.googleapis.com/auth/cloud-platform"

  /// Creates a random callback path for a loopback listener that already owns `port`.
  /// Desktop OAuth clients do not use a client secret and may use a dynamic loopback port.
  static func makeLoopbackRedirectURI(port: UInt16) throws -> URL {
    guard port > 0 else { throw GoogleDesktopOAuthError.invalidLoopbackRedirect }
    let callbackNonce = try randomURLSafeString(byteCount: 24)
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = Int(port)
    components.path = "/dashis/google/oauth/\(callbackNonce)"
    guard let url = components.url else {
      throw GoogleDesktopOAuthError.invalidLoopbackRedirect
    }
    return url
  }

  static func makeAuthorizationFlow(
    clientID: String,
    redirectURI: URL
  ) throws -> GoogleDesktopOAuthFlow {
    let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard validClientID(clientID) else {
      throw GoogleDesktopOAuthError.invalidClientID
    }
    guard validLoopbackRedirect(redirectURI) else {
      throw GoogleDesktopOAuthError.invalidLoopbackRedirect
    }

    let verifier = try randomURLSafeString(byteCount: 32)
    let state = try randomURLSafeString(byteCount: 32)
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()

    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
    components?.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: cloudPlatformScope),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "state", value: state)
    ]
    guard let authorizationURL = components?.url else {
      throw GoogleDesktopOAuthError.invalidAuthorizationURL
    }

    return GoogleDesktopOAuthFlow(
      authorizationURL: authorizationURL,
      redirectURI: redirectURI,
      state: state,
      codeVerifier: verifier
    )
  }

  static func authorizationCode(
    from callbackURL: URL,
    flow: GoogleDesktopOAuthFlow
  ) throws -> String {
    guard sameLoopbackTarget(callbackURL, flow.redirectURI),
          callbackURL.user == nil,
          callbackURL.password == nil,
          callbackURL.fragment == nil,
          let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
    else {
      throw GoogleDesktopOAuthError.invalidCallback
    }

    let names = items.map(\.name)
    guard Set(names).count == names.count else {
      throw GoogleDesktopOAuthError.invalidCallback
    }
    let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    guard constantTimeEqual(values["state"] ?? "", flow.state) else {
      throw GoogleDesktopOAuthError.stateMismatch
    }
    if values["error"] != nil {
      throw GoogleDesktopOAuthError.authorizationDenied
    }
    guard let code = values["code"], validAuthorizationCode(code) else {
      throw GoogleDesktopOAuthError.missingAuthorizationCode
    }
    return code
  }

  static func tokenExchangeRequest(
    authorizationCode: String,
    clientID: String,
    flow: GoogleDesktopOAuthFlow
  ) throws -> URLRequest {
    let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard validClientID(clientID) else {
      throw GoogleDesktopOAuthError.invalidClientID
    }
    guard validAuthorizationCode(authorizationCode),
          validLoopbackRedirect(flow.redirectURI),
          flow.codeVerifier.count >= 43,
          flow.codeVerifier.count <= 128
    else {
      throw GoogleDesktopOAuthError.invalidCallback
    }

    let fields = [
      ("client_id", clientID),
      ("code", authorizationCode),
      ("code_verifier", flow.codeVerifier),
      ("grant_type", "authorization_code"),
      ("redirect_uri", flow.redirectURI.absoluteString)
    ]
    let body = fields
      .map { "\(formEncode($0.0))=\(formEncode($0.1))" }
      .joined(separator: "&")

    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.httpBody = Data(body.utf8)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  /// Intentionally discards `refresh_token` and `id_token`; the returned credential is session-only.
  static func sessionAccessToken(from data: Data, now: Date = Date()) throws -> GoogleSessionAccessToken {
    guard let object = try? JSONSerialization.jsonObject(with: data),
          let root = object as? [String: Any],
          let token = root["access_token"] as? String,
          validAccessToken(token),
          let expiresIn = ProviderJSON.number(root["expires_in"]),
          expiresIn > 0,
          expiresIn <= 7 * 24 * 60 * 60,
          let tokenType = root["token_type"] as? String,
          tokenType.caseInsensitiveCompare("Bearer") == .orderedSame
    else {
      throw GoogleDesktopOAuthError.invalidTokenResponse
    }

    let scope: String?
    if let value = root["scope"] as? String {
      let grantedScopes = Set(value.split(whereSeparator: \.isWhitespace).map(String.init))
      guard grantedScopes == [cloudPlatformScope] else {
        throw GoogleDesktopOAuthError.invalidTokenResponse
      }
      scope = value
    } else {
      scope = nil
    }
    return GoogleSessionAccessToken(
      value: token,
      expiresAt: now.addingTimeInterval(expiresIn),
      grantedScope: scope
    )
  }

  private static func validClientID(_ value: String) -> Bool {
    value.count <= 512
      && value.range(
        of: #"^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$"#,
        options: .regularExpression
      ) != nil
  }

  private static func validLoopbackRedirect(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "http"
      && url.host == "127.0.0.1"
      && url.port != nil
      && url.user == nil
      && url.password == nil
      && url.query == nil
      && url.fragment == nil
      && url.path.hasPrefix("/dashis/google/oauth/")
      && url.path.split(separator: "/").count == 4
  }

  private static func sameLoopbackTarget(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
      && lhs.host?.lowercased() == rhs.host?.lowercased()
      && lhs.port == rhs.port
      && lhs.path == rhs.path
  }

  private static func validAuthorizationCode(_ value: String) -> Bool {
    !value.isEmpty
      && value.count <= 4_096
      && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }

  private static func validAccessToken(_ value: String) -> Bool {
    !value.isEmpty
      && value.count <= 8_192
      && !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
      && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }

  private static func randomURLSafeString(byteCount: Int) throws -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw GoogleDesktopOAuthError.randomGenerationFailed
    }
    return Data(bytes).base64URLEncodedString()
  }

  private static func formEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
  }

  private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for index in left.indices {
      difference |= left[index] ^ right[index]
    }
    return difference == 0
  }
}

private extension Data {
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
