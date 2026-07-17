import Foundation

struct ClaudeUsageClient: ProviderUsageClient {
  struct Context: Sendable {
    let snapshotURL: URL
    let now: Date

    init(snapshotURL: URL = ClaudeSnapshotFile.defaultURL, now: Date = Date()) {
      self.snapshotURL = snapshotURL
      self.now = now
    }
  }

  enum LocalFreshness: String, Hashable, Sendable {
    case fresh
    case stale
    case expired
    case invalidFuture
  }

  let providerID: ProviderID = .claude

  func fetchSnapshot(context: Context) async -> ProviderSnapshot {
    do {
      let localSnapshot = try ClaudeSnapshotFile.read(from: context.snapshotURL)
      let freshness = Self.freshness(of: localSnapshot.observedAt, now: context.now)

      switch freshness {
      case .invalidFuture:
        return emptySnapshot(
          observedAt: context.now,
          warning: "The local Claude snapshot has a future timestamp and was ignored.",
          failure: ProviderFailure(
            operation: "claude_local_snapshot",
            message: "Snapshot timestamp validation failed."
          )
        )
      case .expired:
        return emptySnapshot(
          observedAt: localSnapshot.observedAt,
          warning: "The local Claude snapshot is over 24 hours old. Use Claude Code, then reload.",
          failure: nil
        )
      case .fresh, .stale:
        let windows = makeWindows(from: localSnapshot, now: context.now)
        var warnings: [ProviderWarning] = []
        if freshness == .stale {
          warnings.append(
            ProviderWarning(
              id: "claude-stale",
              message: "Claude usage is based on a local snapshot older than 15 minutes."
            )
          )
        }
        if windows.isEmpty {
          warnings.append(
            ProviderWarning(
              id: "claude-no-windows",
              message: "Claude Code did not provide a supported 5-hour or 7-day window."
            )
          )
        }

        return ProviderSnapshot(
          providerID: providerID,
          scope: .personal("Claude Code"),
          sourceKind: .officialLocalBridge,
          observedAt: localSnapshot.observedAt,
          windows: windows,
          balance: nil,
          metrics: [],
          warnings: warnings,
          partialFailures: []
        )
      }
    } catch let error as ClaudeSnapshotFileError {
      let message: String
      let failure: ProviderFailure?
      switch error {
      case .missing:
        message = "No Claude snapshot yet. Use Claude Code once after connecting, then reload."
        failure = nil
      case .unsafeFile:
        message = "The local Claude snapshot failed its security checks and was ignored."
        failure = ProviderFailure(
          operation: "claude_local_snapshot",
          message: "Snapshot ownership or permissions are unsafe."
        )
      case .tooLarge:
        message = "The local Claude snapshot exceeds the 8 KiB safety limit and was ignored."
        failure = ProviderFailure(
          operation: "claude_local_snapshot",
          message: "Snapshot size validation failed."
        )
      case .invalidPath, .invalidPayload, .unsupportedSchema, .ioFailure:
        message = "The local Claude snapshot could not be validated."
        failure = ProviderFailure(
          operation: "claude_local_snapshot",
          message: error.localizedDescription
        )
      }
      return emptySnapshot(observedAt: context.now, warning: message, failure: failure)
    } catch {
      return emptySnapshot(
        observedAt: context.now,
        warning: "The local Claude snapshot could not be read.",
        failure: ProviderFailure(
          operation: "claude_local_snapshot",
          message: "Unexpected local snapshot failure."
        )
      )
    }
  }

  static func freshness(of observedAt: Date, now: Date = Date()) -> LocalFreshness {
    let age = now.timeIntervalSince(observedAt)
    if age < -60 { return .invalidFuture }
    if age <= 15 * 60 { return .fresh }
    if age <= 24 * 60 * 60 { return .stale }
    return .expired
  }

  private func makeWindows(
    from snapshot: ClaudeSanitizedSnapshot,
    now: Date
  ) -> [QuotaWindow] {
    [
      makeWindow(id: "five-hour", label: "5-hour", value: snapshot.fiveHour, now: now),
      makeWindow(id: "seven-day", label: "7-day", value: snapshot.sevenDay, now: now)
    ].compactMap { $0 }
  }

  private func makeWindow(
    id: String,
    label: String,
    value: ClaudeRateLimitWindowSnapshot?,
    now: Date
  ) -> QuotaWindow? {
    guard let value else { return nil }
    let remainingPercentage = 100 - value.usedPercentage
    let futureReset = value.resetsAt.flatMap { $0 > now ? $0 : nil }
    return QuotaWindow(
      id: id,
      label: label,
      used: nil,
      limit: nil,
      remaining: nil,
      usedPercentage: value.usedPercentage,
      remainingPercentage: remainingPercentage,
      resetsAt: futureReset,
      unit: "%",
      isEstimated: false
    )
  }

  private func emptySnapshot(
    observedAt: Date,
    warning: String,
    failure: ProviderFailure?
  ) -> ProviderSnapshot {
    ProviderSnapshot(
      providerID: providerID,
      scope: .personal("Claude Code"),
      sourceKind: .officialLocalBridge,
      observedAt: observedAt,
      windows: [],
      balance: nil,
      metrics: [],
      warnings: [ProviderWarning(id: "claude-local-state", message: warning)],
      partialFailures: failure.map { [$0] } ?? []
    )
  }
}
