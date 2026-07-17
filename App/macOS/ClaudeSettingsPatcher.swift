import Darwin
import Foundation

enum ClaudeSettingsPatchError: LocalizedError {
  case invalidPath
  case settingsTooLarge
  case unsafeSettingsFile
  case malformedSettings
  case duplicateJSONKey(String)
  case unsupportedStatusLine
  case alreadyConnected
  case notConnected
  case invalidBridgeMarker
  case helperUnavailable
  case concurrentModification
  case ioFailure

  var errorDescription: String? {
    switch self {
    case .invalidPath: "The Claude settings path is invalid."
    case .settingsTooLarge: "Claude settings exceed the local safety limit."
    case .unsafeSettingsFile: "Claude settings failed ownership, type, or permission checks."
    case .malformedSettings: "Claude settings are malformed and were not changed."
    case .duplicateJSONKey(let key): "Claude settings contain a duplicate JSON key: \(key)."
    case .unsupportedStatusLine: "The existing Claude statusLine is not a supported command configuration."
    case .alreadyConnected: "The Dashis Claude bridge is already connected."
    case .notConnected: "The Dashis Claude bridge marker is not present."
    case .invalidBridgeMarker: "The Dashis Claude bridge marker is invalid."
    case .helperUnavailable: "The Dashis Claude bridge helper is unavailable."
    case .concurrentModification: "Claude settings changed while the update was being prepared."
    case .ioFailure: "Claude settings could not be safely read or written."
    }
  }
}

enum ClaudeSettingsPatchKind: String, Sendable {
  case connect
  case disconnect
}

struct ClaudeSettingsPatch: Sendable {
  let kind: ClaudeSettingsPatchKind
  let settingsURL: URL
  let originalData: Data?
  let updatedData: Data
  let summary: String
  fileprivate let expectedFingerprint: ClaudeSettingsFingerprint
  fileprivate let outputPermissions: mode_t
}

private enum ClaudeSettingsFingerprint: Hashable, Sendable {
  case missing
  case present(
    device: UInt64,
    inode: UInt64,
    size: Int64,
    modifiedSeconds: Int64,
    modifiedNanoseconds: Int64,
    mode: UInt16
  )
}

enum ClaudeBridgeInstaller {
  static var defaultInstalledHelperURL: URL {
    ClaudeSnapshotFile.defaultURL
      .deletingLastPathComponent()
      .appendingPathComponent("bin", isDirectory: true)
      .appendingPathComponent("dashis-claude-statusline", isDirectory: false)
  }

  static func installHelper(
    from bundledURL: URL,
    to destinationURL: URL = defaultInstalledHelperURL
  ) throws -> URL {
    guard bundledURL.isFileURL, destinationURL.isFileURL else {
      throw ClaudeSettingsPatchError.invalidPath
    }
    try validateBundledHelper(at: bundledURL)
    let source = Darwin.open(bundledURL.path, O_RDONLY | O_NOFOLLOW)
    guard source >= 0 else { throw ClaudeSettingsPatchError.helperUnavailable }
    defer { Darwin.close(source) }

    var sourceMetadata = stat()
    guard fstat(source, &sourceMetadata) == 0 else {
      throw ClaudeSettingsPatchError.helperUnavailable
    }
    guard sourceMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw ClaudeSettingsPatchError.helperUnavailable
    }
    guard sourceMetadata.st_uid == getuid(),
          sourceMetadata.st_mode & mode_t(0o022) == 0,
          sourceMetadata.st_size >= 0,
          sourceMetadata.st_size <= 32 * 1024 * 1024
    else {
      throw ClaudeSettingsPatchError.helperUnavailable
    }

    let destinationDirectory = destinationURL.deletingLastPathComponent()
    try ensurePrivateDirectory(destinationDirectory.deletingLastPathComponent())
    try ensurePrivateDirectory(destinationDirectory)
    let temporaryURL = destinationDirectory.appendingPathComponent(
      ".helper-\(UUID().uuidString).tmp",
      isDirectory: false
    )
    let destination = Darwin.open(
      temporaryURL.path,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
      mode_t(0o700)
    )
    guard destination >= 0 else { throw ClaudeSettingsPatchError.ioFailure }

    var shouldUnlink = true
    defer {
      Darwin.close(destination)
      if shouldUnlink { Darwin.unlink(temporaryURL.path) }
    }

    try copy(source: source, destination: destination)
    guard fchmod(destination, mode_t(0o700)) == 0, fsync(destination) == 0 else {
      throw ClaudeSettingsPatchError.ioFailure
    }
    guard Darwin.rename(temporaryURL.path, destinationURL.path) == 0 else {
      throw ClaudeSettingsPatchError.ioFailure
    }
    shouldUnlink = false
    return destinationURL
  }

  static func validateBundledHelper(at url: URL) throws {
    guard url.isFileURL else { throw ClaudeSettingsPatchError.invalidPath }
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw ClaudeSettingsPatchError.helperUnavailable }
    defer { Darwin.close(descriptor) }
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
          metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          metadata.st_uid == getuid(),
          metadata.st_mode & mode_t(0o022) == 0,
          metadata.st_size >= 0,
          metadata.st_size <= 32 * 1024 * 1024
    else {
      throw ClaudeSettingsPatchError.helperUnavailable
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
      throw ClaudeSettingsPatchError.ioFailure
    }
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw ClaudeSettingsPatchError.ioFailure }
    guard
      metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
      metadata.st_uid == getuid(),
      metadata.st_mode & mode_t(0o077) == 0
    else {
      throw ClaudeSettingsPatchError.unsafeSettingsFile
    }
  }

  private static func copy(source: Int32, destination: Int32) throws {
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
      let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
        Darwin.read(source, rawBuffer.baseAddress, rawBuffer.count)
      }
      if readCount == 0 { return }
      if readCount < 0 {
        if errno == EINTR { continue }
        throw ClaudeSettingsPatchError.ioFailure
      }
      try buffer.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        var offset = 0
        while offset < readCount {
          let writeCount = Darwin.write(
            destination,
            baseAddress.advanced(by: offset),
            readCount - offset
          )
          if writeCount < 0 {
            if errno == EINTR { continue }
            throw ClaudeSettingsPatchError.ioFailure
          }
          offset += writeCount
        }
      }
    }
  }
}

enum ClaudeSettingsPatcher {
  static let maximumSettingsBytes = 1024 * 1024

  static var defaultSettingsURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude", isDirectory: true)
      .appendingPathComponent("settings.json", isDirectory: false)
  }

  /// Call only from the user-confirmed Connect action. This is the first point
  /// at which the implementation reads `~/.claude/settings.json`.
  static func prepareConnect(
    helperURL: URL,
    settingsURL: URL = defaultSettingsURL,
    requireExistingHelper: Bool = true
  ) throws -> ClaudeSettingsPatch {
    if requireExistingHelper {
      try validateHelper(at: helperURL)
    } else {
      guard helperURL == ClaudeBridgeInstaller.defaultInstalledHelperURL else {
        throw ClaudeSettingsPatchError.invalidPath
      }
    }
    let state = try readSettings(at: settingsURL)
    let source = state.data ?? Data("{}".utf8)
    let document = try JSONTopLevelDocument(data: source)

    var priorCommand: String?
    var replacementObject: [String: Any] = ["type": "command"]
    if let statusLine = document.member(named: "statusLine") {
      let value = source.subdata(in: statusLine.valueRange)
      guard
        let object = try? JSONSerialization.jsonObject(with: value),
        let statusObject = object as? [String: Any],
        statusObject["type"] as? String == "command",
        let command = statusObject["command"] as? String
      else {
        throw ClaudeSettingsPatchError.unsupportedStatusLine
      }
      if command.contains(ClaudeBridgeCommand.markerArgument) {
        guard ClaudeBridgeCommand.isBridgeCommand(command) else {
          throw ClaudeSettingsPatchError.invalidBridgeMarker
        }
        throw ClaudeSettingsPatchError.alreadyConnected
      }
      priorCommand = command
      replacementObject = statusObject
    }

    replacementObject["type"] = "command"
    replacementObject["command"] = try ClaudeBridgeCommand.make(
      helperURL: helperURL,
      priorCommand: priorCommand
    )
    let replacement = try JSONSerialization.data(withJSONObject: replacementObject, options: [.sortedKeys])
    let updated = try document.replacingMember(named: "statusLine", with: replacement)
    guard updated.count <= maximumSettingsBytes else {
      throw ClaudeSettingsPatchError.settingsTooLarge
    }

    return ClaudeSettingsPatch(
      kind: .connect,
      settingsURL: settingsURL,
      originalData: state.data,
      updatedData: updated,
      summary: priorCommand == nil
        ? "Add statusLine.type = command and set statusLine.command to the Dashis helper; preserve every other top-level setting."
        : "Chain the existing statusLine.command through the Dashis helper, preserve the remaining statusLine fields, and retain the prior command for restoration.",
      expectedFingerprint: state.fingerprint,
      outputPermissions: state.permissions
    )
  }

  /// Call only from a user-confirmed Disconnect action.
  static func prepareDisconnect(
    settingsURL: URL = defaultSettingsURL
  ) throws -> ClaudeSettingsPatch {
    let state = try readSettings(at: settingsURL)
    guard let source = state.data else { throw ClaudeSettingsPatchError.notConnected }
    let document = try JSONTopLevelDocument(data: source)
    guard let statusLine = document.member(named: "statusLine") else {
      throw ClaudeSettingsPatchError.notConnected
    }
    let value = source.subdata(in: statusLine.valueRange)
    guard
      let object = try? JSONSerialization.jsonObject(with: value),
      var statusObject = object as? [String: Any],
      statusObject["type"] as? String == "command",
      let command = statusObject["command"] as? String
    else {
      throw ClaudeSettingsPatchError.notConnected
    }
    let priorCommand = try ClaudeBridgeCommand.priorCommand(from: command)

    let updated: Data
    if let priorCommand {
      statusObject["command"] = priorCommand
      let replacement = try JSONSerialization.data(withJSONObject: statusObject, options: [.sortedKeys])
      updated = try document.replacingMember(named: "statusLine", with: replacement)
    } else {
      updated = try document.removingMember(named: "statusLine")
    }

    return ClaudeSettingsPatch(
      kind: .disconnect,
      settingsURL: settingsURL,
      originalData: source,
      updatedData: updated,
      summary: priorCommand == nil
        ? "Remove only the Dashis-managed statusLine member; preserve every other top-level setting."
        : "Restore the prior statusLine.command and preserve the remaining statusLine and top-level fields.",
      expectedFingerprint: state.fingerprint,
      outputPermissions: state.permissions
    )
  }

  static func apply(_ patch: ClaudeSettingsPatch) throws {
    guard patch.settingsURL.isFileURL else { throw ClaudeSettingsPatchError.invalidPath }
    guard patch.updatedData.count <= maximumSettingsBytes else {
      throw ClaudeSettingsPatchError.settingsTooLarge
    }
    guard (try? JSONTopLevelDocument(data: patch.updatedData)) != nil else {
      throw ClaudeSettingsPatchError.malformedSettings
    }
    guard try fingerprint(at: patch.settingsURL) == patch.expectedFingerprint else {
      throw ClaudeSettingsPatchError.concurrentModification
    }

    let directory = patch.settingsURL.deletingLastPathComponent()
    try validateSettingsDirectory(directory)
    let temporaryURL = directory.appendingPathComponent(
      ".dashis-settings-\(UUID().uuidString).tmp",
      isDirectory: false
    )
    let descriptor = Darwin.open(
      temporaryURL.path,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
      patch.outputPermissions
    )
    guard descriptor >= 0 else { throw ClaudeSettingsPatchError.ioFailure }

    var shouldUnlink = true
    defer {
      Darwin.close(descriptor)
      if shouldUnlink { Darwin.unlink(temporaryURL.path) }
    }
    guard fchmod(descriptor, patch.outputPermissions) == 0 else {
      throw ClaudeSettingsPatchError.ioFailure
    }
    try writeAll(patch.updatedData, descriptor: descriptor)
    guard fsync(descriptor) == 0 else { throw ClaudeSettingsPatchError.ioFailure }

    // Recheck immediately before replacement so a preview never knowingly
    // overwrites a settings file changed by Claude Code or the user.
    guard try fingerprint(at: patch.settingsURL) == patch.expectedFingerprint else {
      throw ClaudeSettingsPatchError.concurrentModification
    }
    switch patch.expectedFingerprint {
    case .missing:
      guard Darwin.link(temporaryURL.path, patch.settingsURL.path) == 0 else {
        if errno == EEXIST { throw ClaudeSettingsPatchError.concurrentModification }
        throw ClaudeSettingsPatchError.ioFailure
      }
      guard Darwin.unlink(temporaryURL.path) == 0 else {
        throw ClaudeSettingsPatchError.ioFailure
      }
    case .present:
      guard Darwin.rename(temporaryURL.path, patch.settingsURL.path) == 0 else {
        throw ClaudeSettingsPatchError.ioFailure
      }
    }
    shouldUnlink = false
  }

  private struct SettingsState {
    let data: Data?
    let fingerprint: ClaudeSettingsFingerprint
    let permissions: mode_t
  }

  private static func readSettings(at url: URL) throws -> SettingsState {
    guard url.isFileURL else { throw ClaudeSettingsPatchError.invalidPath }
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else {
      if errno == ENOENT {
        return SettingsState(data: nil, fingerprint: .missing, permissions: mode_t(0o600))
      }
      if errno == ELOOP { throw ClaudeSettingsPatchError.unsafeSettingsFile }
      throw ClaudeSettingsPatchError.ioFailure
    }
    defer { Darwin.close(descriptor) }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0 else { throw ClaudeSettingsPatchError.ioFailure }
    guard
      metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
      metadata.st_uid == getuid(),
      metadata.st_mode & mode_t(0o022) == 0
    else {
      throw ClaudeSettingsPatchError.unsafeSettingsFile
    }
    guard metadata.st_size >= 0, metadata.st_size <= off_t(maximumSettingsBytes) else {
      throw ClaudeSettingsPatchError.settingsTooLarge
    }

    let data = try readAll(descriptor: descriptor, maximumBytes: maximumSettingsBytes)
    _ = try JSONTopLevelDocument(data: data)
    return SettingsState(
      data: data,
      fingerprint: makeFingerprint(metadata),
      permissions: metadata.st_mode & mode_t(0o777)
    )
  }

  private static func validateHelper(at url: URL) throws {
    guard url.isFileURL, url.path.hasPrefix("/") else {
      throw ClaudeSettingsPatchError.invalidPath
    }
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else {
      throw ClaudeSettingsPatchError.helperUnavailable
    }
    guard
      metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
      metadata.st_uid == getuid(),
      metadata.st_mode & mode_t(0o022) == 0,
      metadata.st_mode & mode_t(0o100) != 0
    else {
      throw ClaudeSettingsPatchError.helperUnavailable
    }
  }

  private static func fingerprint(at url: URL) throws -> ClaudeSettingsFingerprint {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else {
      if errno == ENOENT { return .missing }
      throw ClaudeSettingsPatchError.ioFailure
    }
    guard
      metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
      metadata.st_uid == getuid(),
      metadata.st_mode & mode_t(0o022) == 0
    else {
      throw ClaudeSettingsPatchError.unsafeSettingsFile
    }
    return makeFingerprint(metadata)
  }

  private static func makeFingerprint(_ metadata: stat) -> ClaudeSettingsFingerprint {
    .present(
      device: UInt64(metadata.st_dev),
      inode: UInt64(metadata.st_ino),
      size: Int64(metadata.st_size),
      modifiedSeconds: Int64(metadata.st_mtimespec.tv_sec),
      modifiedNanoseconds: Int64(metadata.st_mtimespec.tv_nsec),
      mode: UInt16(metadata.st_mode)
    )
  }

  private static func validateSettingsDirectory(_ url: URL) throws {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw ClaudeSettingsPatchError.ioFailure }
    guard
      metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
      metadata.st_uid == getuid(),
      metadata.st_mode & mode_t(0o022) == 0
    else {
      throw ClaudeSettingsPatchError.unsafeSettingsFile
    }
  }

  private static func readAll(descriptor: Int32, maximumBytes: Int) throws -> Data {
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = buffer.withUnsafeMutableBytes { rawBuffer in
        Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
      }
      if count == 0 { return result }
      if count < 0 {
        if errno == EINTR { continue }
        throw ClaudeSettingsPatchError.ioFailure
      }
      result.append(buffer, count: count)
      if result.count > maximumBytes { throw ClaudeSettingsPatchError.settingsTooLarge }
    }
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
          throw ClaudeSettingsPatchError.ioFailure
        }
        offset += count
      }
    }
  }
}

private struct JSONTopLevelDocument {
  struct Member {
    let name: String
    let memberRange: Range<Int>
    let valueRange: Range<Int>
  }

  private let data: Data
  private let members: [Member]
  private let closingBraceOffset: Int

  init(data: Data) throws {
    var scanner = JSONByteScanner(data: data)
    let result = try scanner.scanTopLevelObject()
    self.data = data
    members = result.members
    closingBraceOffset = result.closingBraceOffset
  }

  func member(named name: String) -> Member? {
    members.first { $0.name == name }
  }

  func replacingMember(named name: String, with value: Data) throws -> Data {
    var updated = data
    if let member = member(named: name) {
      updated.replaceSubrange(member.valueRange, with: value)
    } else {
      let prefix = members.isEmpty ? "\"\(name)\":" : ",\"\(name)\":"
      updated.insert(contentsOf: Data(prefix.utf8) + value, at: closingBraceOffset)
    }
    guard (try? JSONSerialization.jsonObject(with: updated)) != nil else {
      throw ClaudeSettingsPatchError.malformedSettings
    }
    return updated
  }

  func removingMember(named name: String) throws -> Data {
    guard let index = members.firstIndex(where: { $0.name == name }) else {
      throw ClaudeSettingsPatchError.notConnected
    }
    var updated = data
    let removalRange: Range<Int>
    if members.count == 1 {
      removalRange = members[index].memberRange
    } else if index < members.index(before: members.endIndex) {
      removalRange = members[index].memberRange.lowerBound ..< members[index + 1].memberRange.lowerBound
    } else {
      removalRange = members[index - 1].memberRange.upperBound ..< members[index].memberRange.upperBound
    }
    updated.removeSubrange(removalRange)
    guard (try? JSONSerialization.jsonObject(with: updated)) != nil else {
      throw ClaudeSettingsPatchError.malformedSettings
    }
    return updated
  }
}

private struct JSONByteScanner {
  private let bytes: [UInt8]
  private var offset = 0

  init(data: Data) {
    bytes = Array(data)
  }

  mutating func scanTopLevelObject() throws -> (
    members: [JSONTopLevelDocument.Member],
    closingBraceOffset: Int
  ) {
    skipWhitespace()
    guard consume(ascii: "{") else { throw ClaudeSettingsPatchError.malformedSettings }
    skipWhitespace()
    var members: [JSONTopLevelDocument.Member] = []
    var names = Set<String>()

    if peek(ascii: "}") {
      let closing = offset
      offset += 1
      try requireEnd()
      return (members, closing)
    }

    while true {
      let memberStart = offset
      let name = try scanStringValue()
      guard names.insert(name).inserted else {
        throw ClaudeSettingsPatchError.duplicateJSONKey(name)
      }
      skipWhitespace()
      guard consume(ascii: ":") else { throw ClaudeSettingsPatchError.malformedSettings }
      skipWhitespace()
      let valueStart = offset
      try scanValue()
      let valueEnd = offset
      members.append(
        JSONTopLevelDocument.Member(
          name: name,
          memberRange: memberStart ..< valueEnd,
          valueRange: valueStart ..< valueEnd
        )
      )
      skipWhitespace()
      if consume(ascii: ",") {
        skipWhitespace()
        continue
      }
      guard peek(ascii: "}") else { throw ClaudeSettingsPatchError.malformedSettings }
      let closing = offset
      offset += 1
      try requireEnd()
      return (members, closing)
    }
  }

  private mutating func scanValue() throws {
    guard offset < bytes.count else { throw ClaudeSettingsPatchError.malformedSettings }
    switch bytes[offset] {
    case ascii("\""):
      _ = try scanStringValue()
    case ascii("{"):
      try scanObject()
    case ascii("["):
      try scanArray()
    default:
      try scanPrimitive()
    }
  }

  private mutating func scanObject() throws {
    guard consume(ascii: "{") else { throw ClaudeSettingsPatchError.malformedSettings }
    skipWhitespace()
    if consume(ascii: "}") { return }
    var names = Set<String>()
    while true {
      let name = try scanStringValue()
      guard names.insert(name).inserted else {
        throw ClaudeSettingsPatchError.duplicateJSONKey(name)
      }
      skipWhitespace()
      guard consume(ascii: ":") else { throw ClaudeSettingsPatchError.malformedSettings }
      skipWhitespace()
      try scanValue()
      skipWhitespace()
      if consume(ascii: ",") {
        skipWhitespace()
        continue
      }
      guard consume(ascii: "}") else { throw ClaudeSettingsPatchError.malformedSettings }
      return
    }
  }

  private mutating func scanArray() throws {
    guard consume(ascii: "[") else { throw ClaudeSettingsPatchError.malformedSettings }
    skipWhitespace()
    if consume(ascii: "]") { return }
    while true {
      try scanValue()
      skipWhitespace()
      if consume(ascii: ",") {
        skipWhitespace()
        continue
      }
      guard consume(ascii: "]") else { throw ClaudeSettingsPatchError.malformedSettings }
      return
    }
  }

  private mutating func scanStringValue() throws -> String {
    let start = offset
    guard consume(ascii: "\"") else { throw ClaudeSettingsPatchError.malformedSettings }
    while offset < bytes.count {
      let byte = bytes[offset]
      offset += 1
      if byte == ascii("\"") {
        let raw = Data(bytes[start ..< offset])
        guard let value = try? JSONDecoder().decode(String.self, from: raw) else {
          throw ClaudeSettingsPatchError.malformedSettings
        }
        return value
      }
      if byte == ascii("\\") {
        guard offset < bytes.count else { throw ClaudeSettingsPatchError.malformedSettings }
        let escape = bytes[offset]
        offset += 1
        if escape == ascii("u") {
          guard offset + 4 <= bytes.count else { throw ClaudeSettingsPatchError.malformedSettings }
          for digit in bytes[offset ..< offset + 4] where !isHexDigit(digit) {
            _ = digit
            throw ClaudeSettingsPatchError.malformedSettings
          }
          offset += 4
        } else if ![ascii("\""), ascii("\\"), ascii("/"), ascii("b"), ascii("f"), ascii("n"), ascii("r"), ascii("t")].contains(escape) {
          throw ClaudeSettingsPatchError.malformedSettings
        }
      } else if byte < 0x20 {
        throw ClaudeSettingsPatchError.malformedSettings
      }
    }
    throw ClaudeSettingsPatchError.malformedSettings
  }

  private mutating func scanPrimitive() throws {
    let start = offset
    while offset < bytes.count {
      let byte = bytes[offset]
      if byte == ascii(",") || byte == ascii("}") || byte == ascii("]") || isWhitespace(byte) {
        break
      }
      offset += 1
    }
    guard offset > start else { throw ClaudeSettingsPatchError.malformedSettings }
    let token = Data(bytes[start ..< offset])
    guard (try? JSONSerialization.jsonObject(with: token, options: [.fragmentsAllowed])) != nil else {
      throw ClaudeSettingsPatchError.malformedSettings
    }
  }

  private mutating func requireEnd() throws {
    skipWhitespace()
    guard offset == bytes.count else { throw ClaudeSettingsPatchError.malformedSettings }
  }

  private mutating func skipWhitespace() {
    while offset < bytes.count, isWhitespace(bytes[offset]) { offset += 1 }
  }

  private mutating func consume(ascii character: Character) -> Bool {
    guard peek(ascii: character) else { return false }
    offset += 1
    return true
  }

  private func peek(ascii character: Character) -> Bool {
    offset < bytes.count && bytes[offset] == ascii(character)
  }

  private func ascii(_ character: Character) -> UInt8 {
    character.asciiValue!
  }

  private func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
  }

  private func isHexDigit(_ byte: UInt8) -> Bool {
    (0x30 ... 0x39).contains(byte)
      || (0x41 ... 0x46).contains(byte)
      || (0x61 ... 0x66).contains(byte)
  }
}
