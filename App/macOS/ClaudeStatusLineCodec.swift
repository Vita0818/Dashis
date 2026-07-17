import CoreFoundation
import Darwin
import Foundation

struct ClaudeRateLimitWindowSnapshot: Codable, Hashable, Sendable {
  let usedPercentage: Double
  let resetsAt: Date?
}

struct ClaudeSanitizedSnapshot: Codable, Hashable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let observedAt: Date
  let fiveHour: ClaudeRateLimitWindowSnapshot?
  let sevenDay: ClaudeRateLimitWindowSnapshot?

  init(
    observedAt: Date,
    fiveHour: ClaudeRateLimitWindowSnapshot?,
    sevenDay: ClaudeRateLimitWindowSnapshot?
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.observedAt = observedAt
    self.fiveHour = fiveHour
    self.sevenDay = sevenDay
  }
}

struct ClaudeStatusLineUpdate: Hashable, Sendable {
  let observedAt: Date
  let fiveHour: ClaudeRateLimitWindowSnapshot?
  let sevenDay: ClaudeRateLimitWindowSnapshot?

  var hasAnyWindow: Bool {
    fiveHour != nil || sevenDay != nil
  }
}

enum ClaudeStatusLineParseResult: Hashable, Sendable {
  case noRateLimits
  case update(ClaudeStatusLineUpdate)
}

enum ClaudeSnapshotFileError: LocalizedError {
  case missing
  case invalidPath
  case unsafeFile
  case tooLarge
  case invalidPayload
  case unsupportedSchema
  case ioFailure

  var errorDescription: String? {
    switch self {
    case .missing: "The Claude bridge has not produced a snapshot yet."
    case .invalidPath: "The Claude bridge snapshot path is invalid."
    case .unsafeFile: "The Claude bridge snapshot failed its ownership or permission check."
    case .tooLarge: "The Claude bridge snapshot exceeds the 8 KiB safety limit."
    case .invalidPayload: "The Claude bridge snapshot is malformed."
    case .unsupportedSchema: "The Claude bridge snapshot uses an unsupported schema."
    case .ioFailure: "The Claude bridge snapshot could not be read or written."
    }
  }
}

enum ClaudeStatusLineCodec {
  static func parse(_ input: Data, observedAt: Date = Date()) -> ClaudeStatusLineParseResult {
    guard
      let root = try? JSONSerialization.jsonObject(with: input, options: []),
      let object = root as? [String: Any],
      let rateLimits = object["rate_limits"] as? [String: Any]
    else {
      return .noRateLimits
    }

    let update = ClaudeStatusLineUpdate(
      observedAt: observedAt,
      fiveHour: parseWindow(rateLimits["five_hour"]),
      sevenDay: parseWindow(rateLimits["seven_day"])
    )
    return .update(update)
  }

  static func merge(
    _ update: ClaudeStatusLineUpdate,
    into existing: ClaudeSanitizedSnapshot?
  ) -> ClaudeSanitizedSnapshot? {
    guard update.hasAnyWindow else { return nil }

    let retainedFiveHour = update.fiveHour == nil && existing?.fiveHour != nil
    let retainedSevenDay = update.sevenDay == nil && existing?.sevenDay != nil
    let providedWindowChanged = existing.map { existing in
      (update.fiveHour != nil && update.fiveHour != existing.fiveHour)
        || (update.sevenDay != nil && update.sevenDay != existing.sevenDay)
    } ?? true
    let observedAt: Date
    if !providedWindowChanged, let existing {
      // Claude may invoke statusLine for non-response events. Identical fields
      // must not make an old quota observation look freshly sampled.
      observedAt = existing.observedAt
    } else if (retainedFiveHour || retainedSevenDay), let existing {
      // A single status-line payload may omit either window. Keep that window's
      // last value, but conservatively retain the older global observation time.
      observedAt = min(existing.observedAt, update.observedAt)
    } else {
      observedAt = update.observedAt
    }

    return ClaudeSanitizedSnapshot(
      observedAt: observedAt,
      fiveHour: update.fiveHour ?? existing?.fiveHour,
      sevenDay: update.sevenDay ?? existing?.sevenDay
    )
  }

  private static func parseWindow(_ value: Any?) -> ClaudeRateLimitWindowSnapshot? {
    guard
      let object = value as? [String: Any],
      let usedPercentage = finiteNumber(object["used_percentage"]),
      (0 ... 100).contains(usedPercentage)
    else {
      return nil
    }

    let resetsAt: Date?
    if let rawReset = object["resets_at"], !(rawReset is NSNull) {
      guard let epochSeconds = epochSeconds(rawReset) else { return nil }
      resetsAt = Date(timeIntervalSince1970: epochSeconds)
    } else {
      resetsAt = nil
    }

    return ClaudeRateLimitWindowSnapshot(
      usedPercentage: usedPercentage,
      resetsAt: resetsAt
    )
  }

  private static func finiteNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else { return nil }
    guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let result = number.doubleValue
    return result.isFinite ? result : nil
  }

  private static func epochSeconds(_ value: Any) -> TimeInterval? {
    guard let seconds = finiteNumber(value) else { return nil }
    guard seconds >= 0, seconds.rounded(.towardZero) == seconds else { return nil }
    // Current millisecond epochs are above one trillion. Unix seconds remain
    // below ten billion until the 23rd century, which is ample for quota resets.
    guard seconds < 10_000_000_000 else { return nil }
    return seconds
  }
}

enum ClaudeBridgeCommand {
  static let markerArgument = "--dashis-marker-v1"
  static let priorCommandArgument = "--dashis-prior-command-base64"

  static func make(helperURL: URL, priorCommand: String?) throws -> String {
    guard helperURL.isFileURL, helperURL.path.hasPrefix("/") else {
      throw ClaudeBridgeCommandError.invalidPath
    }
    let priorData = Data((priorCommand ?? "").utf8)
    guard priorData.count <= 64 * 1024, !(priorCommand ?? "").contains("\0") else {
      throw ClaudeBridgeCommandError.invalidPriorCommand
    }
    let encodedPrior = priorData.base64EncodedString()
    return [
      shellQuote(helperURL.path),
      markerArgument,
      priorCommandArgument,
      shellQuote(encodedPrior)
    ].joined(separator: " ")
  }

  static func priorCommand(from command: String) throws -> String? {
    let needle = " \(markerArgument) \(priorCommandArgument) '"
    guard let markerRange = command.range(of: needle, options: .backwards) else {
      throw ClaudeBridgeCommandError.notBridgeCommand
    }
    let encodedStart = markerRange.upperBound
    guard command.hasSuffix("'") else { throw ClaudeBridgeCommandError.invalidMarker }
    let encodedEnd = command.index(before: command.endIndex)
    guard encodedStart <= encodedEnd else { throw ClaudeBridgeCommandError.invalidMarker }
    let encoded = String(command[encodedStart ..< encodedEnd])
    guard encoded.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=".contains($0)) }) else {
      throw ClaudeBridgeCommandError.invalidMarker
    }
    guard let data = Data(base64Encoded: encoded), data.count <= 64 * 1024 else {
      throw ClaudeBridgeCommandError.invalidMarker
    }
    guard let prior = String(data: data, encoding: .utf8) else {
      throw ClaudeBridgeCommandError.invalidMarker
    }
    return prior.isEmpty ? nil : prior
  }

  static func isBridgeCommand(_ command: String) -> Bool {
    guard command.contains(" \(markerArgument) \(priorCommandArgument) '") else { return false }
    do {
      _ = try priorCommand(from: command)
      return true
    } catch {
      return false
    }
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

enum ClaudeBridgeCommandError: LocalizedError {
  case invalidPath
  case notBridgeCommand
  case invalidMarker
  case invalidPriorCommand

  var errorDescription: String? {
    switch self {
    case .invalidPath: "The Claude bridge helper path is invalid."
    case .notBridgeCommand: "The Dashis Claude bridge marker is not present."
    case .invalidMarker: "The Dashis Claude bridge marker is invalid."
    case .invalidPriorCommand: "The existing Claude statusLine command cannot be safely chained."
    }
  }
}

enum ClaudeSnapshotFile {
  static let maximumBytes = 8 * 1024

  static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
      .appendingPathComponent("com.vitemis.dashis", isDirectory: true)
      .appendingPathComponent("ClaudeBridge", isDirectory: true)
      .appendingPathComponent("snapshot.json", isDirectory: false)
  }

  static func read(from url: URL = defaultURL) throws -> ClaudeSanitizedSnapshot {
    guard url.isFileURL else { throw ClaudeSnapshotFileError.invalidPath }
    let path = url.path
    let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else {
      if errno == ENOENT { throw ClaudeSnapshotFileError.missing }
      if errno == ELOOP { throw ClaudeSnapshotFileError.unsafeFile }
      throw ClaudeSnapshotFileError.ioFailure
    }
    defer { Darwin.close(descriptor) }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0 else {
      throw ClaudeSnapshotFileError.ioFailure
    }
    guard isRegular(metadata.st_mode), metadata.st_uid == getuid() else {
      throw ClaudeSnapshotFileError.unsafeFile
    }
    guard metadata.st_mode & mode_t(0o077) == 0 else {
      throw ClaudeSnapshotFileError.unsafeFile
    }
    guard metadata.st_size >= 0, metadata.st_size <= off_t(maximumBytes) else {
      throw ClaudeSnapshotFileError.tooLarge
    }

    let data = try readAll(descriptor: descriptor, maximumBytes: maximumBytes)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let snapshot = try? decoder.decode(ClaudeSanitizedSnapshot.self, from: data) else {
      throw ClaudeSnapshotFileError.invalidPayload
    }
    guard snapshot.schemaVersion == ClaudeSanitizedSnapshot.currentSchemaVersion else {
      throw ClaudeSnapshotFileError.unsupportedSchema
    }
    guard validate(snapshot) else { throw ClaudeSnapshotFileError.invalidPayload }
    return snapshot
  }

  static func write(
    _ snapshot: ClaudeSanitizedSnapshot,
    to url: URL = defaultURL
  ) throws {
    guard url.isFileURL else { throw ClaudeSnapshotFileError.invalidPath }
    guard validate(snapshot) else { throw ClaudeSnapshotFileError.invalidPayload }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(snapshot)
    guard data.count <= maximumBytes else { throw ClaudeSnapshotFileError.tooLarge }

    let directory = url.deletingLastPathComponent()
    try ensurePrivateDirectory(directory)

    let temporaryURL = directory.appendingPathComponent(
      ".snapshot-\(UUID().uuidString).tmp",
      isDirectory: false
    )
    let descriptor = Darwin.open(
      temporaryURL.path,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
      mode_t(0o600)
    )
    guard descriptor >= 0 else { throw ClaudeSnapshotFileError.ioFailure }

    var shouldUnlink = true
    defer {
      Darwin.close(descriptor)
      if shouldUnlink { Darwin.unlink(temporaryURL.path) }
    }

    guard fchmod(descriptor, mode_t(0o600)) == 0 else {
      throw ClaudeSnapshotFileError.ioFailure
    }
    try writeAll(data, descriptor: descriptor)
    guard fsync(descriptor) == 0 else { throw ClaudeSnapshotFileError.ioFailure }
    guard Darwin.rename(temporaryURL.path, url.path) == 0 else {
      throw ClaudeSnapshotFileError.ioFailure
    }
    shouldUnlink = false
  }

  /// Removes only a validated Dashis snapshot. Call from an explicit Clear or
  /// Disconnect action; this function is never invoked automatically.
  static func remove(at url: URL = defaultURL) throws {
    guard url.isFileURL else { throw ClaudeSnapshotFileError.invalidPath }
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else {
      if errno == ENOENT { return }
      throw ClaudeSnapshotFileError.ioFailure
    }
    guard
      isRegular(metadata.st_mode),
      metadata.st_uid == getuid(),
      metadata.st_mode & mode_t(0o077) == 0
    else {
      throw ClaudeSnapshotFileError.unsafeFile
    }
    guard Darwin.unlink(url.path) == 0 else { throw ClaudeSnapshotFileError.ioFailure }
  }

  private static func validate(_ snapshot: ClaudeSanitizedSnapshot) -> Bool {
    guard snapshot.observedAt.timeIntervalSince1970.isFinite else { return false }
    return [snapshot.fiveHour, snapshot.sevenDay].allSatisfy { window in
      guard let window else { return true }
      guard window.usedPercentage.isFinite, (0 ... 100).contains(window.usedPercentage) else {
        return false
      }
      guard let resetsAt = window.resetsAt else { return true }
      let seconds = resetsAt.timeIntervalSince1970
      return seconds.isFinite && seconds >= 0 && seconds < 10_000_000_000
    }
  }

  private static func ensurePrivateDirectory(_ url: URL) throws {
    do {
      try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: 0o700)]
      )
    } catch {
      throw ClaudeSnapshotFileError.ioFailure
    }

    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw ClaudeSnapshotFileError.ioFailure }
    guard isDirectory(metadata.st_mode), metadata.st_uid == getuid() else {
      throw ClaudeSnapshotFileError.unsafeFile
    }
    guard metadata.st_mode & mode_t(0o077) == 0 else {
      throw ClaudeSnapshotFileError.unsafeFile
    }
  }

  private static func readAll(descriptor: Int32, maximumBytes: Int) throws -> Data {
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 2048)
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        throw ClaudeSnapshotFileError.ioFailure
      }
      result.append(buffer, count: count)
      if result.count > maximumBytes { throw ClaudeSnapshotFileError.tooLarge }
    }
    return result
  }

  private static func writeAll(_ data: Data, descriptor: Int32) throws {
    try data.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else { return }
      var offset = 0
      while offset < rawBuffer.count {
        let count = Darwin.write(
          descriptor,
          baseAddress.advanced(by: offset),
          rawBuffer.count - offset
        )
        if count < 0 {
          if errno == EINTR { continue }
          throw ClaudeSnapshotFileError.ioFailure
        }
        offset += count
      }
    }
  }

  private static func isRegular(_ mode: mode_t) -> Bool {
    mode & mode_t(S_IFMT) == mode_t(S_IFREG)
  }

  private static func isDirectory(_ mode: mode_t) -> Bool {
    mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
  }
}
