import CoreFoundation
import Foundation

enum ProviderJSON {
  static func dictionary(_ value: Any?) -> [String: Any] {
    value as? [String: Any] ?? [:]
  }

  static func optionalDictionary(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
  }

  static func array(_ value: Any?) -> [Any] {
    value as? [Any] ?? []
  }

  static func string(_ value: Any?) -> String? {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return nil
  }

  static func number(_ value: Any?) -> Double? {
    if let value = value as? NSNumber,
       CFGetTypeID(value) == CFBooleanGetTypeID() {
      return nil
    }
    let result: Double?
    if let value = value as? Double {
      result = value
    } else if let value = value as? Int {
      result = Double(value)
    } else if let value = value as? NSNumber {
      result = CFGetTypeID(value) == CFBooleanGetTypeID() ? nil : value.doubleValue
    } else if let value = value as? String {
      result = Double(value)
    } else {
      result = nil
    }
    guard let result, result.isFinite else { return nil }
    return result
  }

  static func int(_ value: Any?) -> Int? {
    guard let value = number(value) else { return nil }
    return Int(exactly: value)
  }

  static func bool(_ value: Any?) -> Bool? {
    if let value = value as? NSNumber {
      return CFGetTypeID(value) == CFBooleanGetTypeID() ? value.boolValue : nil
    }
    if let value = value as? String {
      if value == "true" { return true }
      if value == "false" { return false }
    }
    return nil
  }

  static func date(_ value: Any?) -> Date? {
    guard let value = string(value) else { return nil }
    return ISO8601DateFormatter.providerFlexible.date(from: value)
      ?? ISO8601DateFormatter.providerStandard.date(from: value)
  }

  static func safeMessage(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
      return description
    }
    return "The provider check failed."
  }

  static func clampForDisplay(_ value: Double) -> Double {
    Swift.max(0, Swift.min(100, value))
  }
}

extension ISO8601DateFormatter {
  static let providerFlexible: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static let providerStandard = ISO8601DateFormatter()
}

func captureProviderResult<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
  do {
    return .success(try await operation())
  } catch {
    return .failure(error)
  }
}
