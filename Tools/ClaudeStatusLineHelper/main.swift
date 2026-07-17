import Darwin
import Foundation

enum ClaudeStatusLineHelperMain {
  private static let maximumInputBytes = 1024 * 1024

  static func main() {
    guard let invocation = parseInvocation(arguments: Array(CommandLine.arguments.dropFirst())) else {
      exit(64)
    }

    guard let priorCommand = invocation.priorCommand else {
      if let input = readBoundedInput() {
        updateSanitizedSnapshot(from: input)
      }
      exit(EXIT_SUCCESS)
    }
    let result = runPriorCommand(priorCommand)
    if let input = result.input {
      updateSanitizedSnapshot(from: input)
    }
    exit(result.status)
  }

  private struct Invocation {
    let priorCommand: String?
  }

  private static func parseInvocation(arguments: [String]) -> Invocation? {
    guard
      arguments.count == 3,
      arguments[0] == ClaudeBridgeCommand.markerArgument,
      arguments[1] == ClaudeBridgeCommand.priorCommandArgument,
      let data = Data(base64Encoded: arguments[2]),
      data.count <= 64 * 1024,
      let command = String(data: data, encoding: .utf8),
      !command.contains("\0")
    else {
      return nil
    }
    return Invocation(priorCommand: command.isEmpty ? nil : command)
  }

  private static func updateSanitizedSnapshot(from rawInput: Data) {
    guard case .update(let update) = ClaudeStatusLineCodec.parse(rawInput) else {
      // `rate_limits` is optional. Its absence must never erase a valid snapshot.
      return
    }
    guard update.hasAnyWindow else { return }

    let existing: ClaudeSanitizedSnapshot?
    do {
      existing = try ClaudeSnapshotFile.read()
    } catch ClaudeSnapshotFileError.missing {
      existing = nil
    } catch {
      // Fail closed: an unsafe or malformed existing file is never overwritten.
      return
    }

    guard let merged = ClaudeStatusLineCodec.merge(update, into: existing) else { return }
    try? ClaudeSnapshotFile.write(merged)
  }

  private static func readBoundedInput() -> Data? {
    var input = Data()
    while input.count <= maximumInputBytes {
      let remaining = maximumInputBytes - input.count + 1
      let chunk: Data
      do {
        guard let next = try FileHandle.standardInput.read(upToCount: min(64 * 1024, remaining)),
              !next.isEmpty
        else {
          return input
        }
        chunk = next
      } catch {
        return nil
      }
      input.append(chunk)
    }
    return nil
  }

  private static func runPriorCommand(_ command: String) -> (status: Int32, input: Data?) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    let inputPipe = Pipe()
    process.standardInput = inputPipe
    do {
      try process.run()
    } catch {
      return (127, readBoundedInput())
    }

    var captured = Data()
    var captureIsValid = true
    var canForward = true
    while true {
      let chunk: Data
      do {
        guard let next = try FileHandle.standardInput.read(upToCount: 64 * 1024), !next.isEmpty else {
          break
        }
        chunk = next
      } catch {
        captureIsValid = false
        break
      }
      if captureIsValid {
        if chunk.count <= maximumInputBytes - captured.count {
          captured.append(chunk)
        } else {
          captureIsValid = false
          captured.removeAll(keepingCapacity: false)
        }
      }
      if canForward {
        do {
          try inputPipe.fileHandleForWriting.write(contentsOf: chunk)
        } catch {
          // The prior command may intentionally close stdin early. Continue
          // draining our stdin while preserving its own exit status.
          canForward = false
        }
      }
    }
    try? inputPipe.fileHandleForWriting.close()
    process.waitUntilExit()

    switch process.terminationReason {
    case .exit:
      return (process.terminationStatus, captureIsValid ? captured : nil)
    case .uncaughtSignal:
      return (128 + process.terminationStatus, captureIsValid ? captured : nil)
    @unknown default:
      return (process.terminationStatus, captureIsValid ? captured : nil)
    }
  }
}

ClaudeStatusLineHelperMain.main()
