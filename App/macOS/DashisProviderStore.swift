import AppKit
import Foundation

enum DashisOpenRouterMode: String, CaseIterable, Identifiable {
  case oauthKey = "OAuth key"
  case management = "Management key"

  var id: String { rawValue }
}

enum DashisGoogleMode: String, CaseIterable, Identifiable {
  case consumer = "Consumer subscription"
  case cloudProject = "Gemini API project"

  var id: String { rawValue }
}

@MainActor
final class DashisProviderStore: ObservableObject {
  @Published private(set) var providers: [DashisProvider] = [
    .codex, .claude, .googleAI, .openRouter
  ]
  @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
  @Published private var loadingProviderIDs: Set<String> = []

  @Published var codexWorkspaceID = ""
  @Published var codexAnalyticsAPIKey = ""
  @Published var codexAnalyticsDays = 30

  @Published var openRouterMode: DashisOpenRouterMode = .oauthKey {
    didSet {
      guard oldValue != openRouterMode else { return }
      handleOpenRouterModeChange()
    }
  }
  @Published var openRouterManagementAPIKey = ""
  @Published var openRouterGenerationID = ""
  @Published var openRouterAnalyticsDays = 30
  @Published private(set) var openRouterConnectionMessage = "Not connected"
  @Published private var openRouterOAuthAPIKey: String?

  @Published var googleMode: DashisGoogleMode = .consumer {
    didSet {
      guard oldValue != googleMode else { return }
      handleGoogleModeChange()
    }
  }
  @Published var googleManualUsed = ""
  @Published var googleManualLimit = ""
  @Published var googleManualRemaining = ""
  @Published var googleManualUnit = "%"
  @Published var googleProjectID = ""
  @Published var googleOAuthClientID = ""
  @Published var googleQuotaIDs = ""
  @Published private(set) var googleConnectionMessage = "Not connected"
  @Published private var googleAccessToken: GoogleSessionAccessToken?

  @Published private(set) var claudePatchSummary: String?
  @Published private(set) var claudeConnectionMessage = "Bridge not configured"
  @Published private var claudePendingPatch: ClaudeSettingsPatch?
  private var claudePendingBundledHelper: URL?

  private let service: DashisProviderService
  private var sessionGenerations: [ProviderID: Int] = [:]
  private var activeOperationIDs: [ProviderID: UUID] = [:]
  private var activeOperationCancellations: [ProviderID: (id: UUID, cancel: () -> Void)] = [:]

  init(service: DashisProviderService = DashisProviderService()) {
    self.service = service
#if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--visual-qa") {
      apply(Self.visualQASnapshot())
    }
#endif
  }

#if DEBUG
  private static func visualQASnapshot(now: Date = Date()) -> ProviderSnapshot {
    ProviderSnapshot(
      providerID: .codex,
      scope: .personal("pro"),
      sourceKind: .experimentalPrivate,
      observedAt: now,
      windows: [
        QuotaWindow(
          id: "visual-qa-weekly",
          label: "Weekly usage limit",
          used: 6,
          limit: 100,
          remaining: 94,
          usedPercentage: 6,
          remainingPercentage: 94,
          resetsAt: now.addingTimeInterval(7 * 24 * 60 * 60),
          unit: "%",
          isEstimated: false
        ),
        QuotaWindow(
          id: "visual-qa-model",
          label: "GPT-5.3-Codex-Spark",
          used: 0,
          limit: 100,
          remaining: 100,
          usedPercentage: 0,
          remainingPercentage: 100,
          resetsAt: nil,
          unit: "%",
          isEstimated: false
        )
      ],
      balance: ProviderBalance(
        label: "Credits remaining",
        used: nil,
        limit: nil,
        remaining: 0,
        unit: "credits",
        resetDescription: nil
      ),
      metrics: [
        ProviderMetric(
          key: "reset_credits",
          label: "Available reset credits",
          value: 5,
          unit: "credits"
        )
      ],
      warnings: [
        ProviderWarning(
          id: "visual-qa-experimental",
          message: "Personal Codex usage uses an experimental, non-public desktop endpoint."
        )
      ],
      partialFailures: []
    )
  }
#endif

  var isOpenRouterOAuthConnected: Bool {
    openRouterOAuthAPIKey != nil
  }

  var isGoogleProjectConnected: Bool {
    guard let token = googleAccessToken else { return false }
    return token.isUsable()
  }

  var hasClaudePendingPatch: Bool {
    claudePendingPatch != nil
  }

  func provider(id: String) -> DashisProvider? {
    providers.first { $0.id == id }
  }

  func title(for selectionID: String) -> String {
    if selectionID == DashisSelection.dashboard { return "Dashboard" }
    if selectionID == DashisSelection.settings { return "Settings" }
    return provider(id: selectionID)?.name ?? "Dashboard"
  }

  func isLoading(_ providerID: String) -> Bool {
    loadingProviderIDs.contains(providerID)
  }

  func runPrimaryCheck(for providerID: String) async {
    switch providerID {
    case ProviderID.codex.rawValue:
      await checkCodexDesktop()
    case ProviderID.claude.rawValue:
      await reloadClaudeSnapshot()
    case ProviderID.google.rawValue:
      if googleMode == .consumer {
        openGoogleConsumerQuotaPage()
      } else {
        await checkGoogleProject()
      }
    case ProviderID.openRouter.rawValue:
      if openRouterMode == .management {
        await checkOpenRouterManagement()
      } else if isOpenRouterOAuthConnected {
        await checkOpenRouterOAuthKey()
      } else {
        await connectOpenRouterOAuth()
      }
    default:
      break
    }
  }

  func checkCodexDesktop() async {
    let operationID = beginOperation(for: .codex)
    let generation = sessionGeneration(for: .codex)
    defer { endOperation(for: .codex, id: operationID) }
    guard let snapshot = await awaitOperation(for: .codex, id: operationID, {
      await self.service.codex.fetchPersonalSnapshot()
    }) else { return }
    guard generation == sessionGeneration(for: .codex) else { return }
    apply(snapshot)
  }

  func checkCodexAnalytics() async {
    let workspaceID = codexWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKey = codexAnalyticsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !workspaceID.isEmpty, !apiKey.isEmpty else {
      invalidateSession(for: .codex)
      applyError(
        providerID: .codex,
        scope: .workspace(workspaceID.isEmpty ? "Codex workspace" : workspaceID),
        source: .officialDirect,
        operation: "codex.enterprise.input",
        message: workspaceID.isEmpty ? "Enter a workspace ID." : "Enter an analytics API key."
      )
      return
    }

    let operationID = beginOperation(for: .codex)
    defer { endOperation(for: .codex, id: operationID) }
    let generation = sessionGeneration(for: .codex)
    let days = codexAnalyticsDays
    guard let snapshot = await awaitOperation(for: .codex, id: operationID, {
      await self.service.codex.fetchEnterpriseSnapshot(
        apiKey: apiKey,
        workspaceID: workspaceID,
        days: days
      )
    }) else { return }
    guard generation == sessionGeneration(for: .codex) else { return }
    apply(snapshot)
  }

  func clearCodexSession() {
    invalidateSession(for: .codex)
    codexWorkspaceID = ""
    codexAnalyticsAPIKey = ""
    codexAnalyticsDays = 30
    clearSnapshot(for: .codex, base: .codex, message: "Codex inputs and loaded snapshot cleared from app memory.")
  }

  func reloadClaudeSnapshot() async {
    let operationID = beginOperation(for: .claude)
    let generation = sessionGeneration(for: .claude)
    defer { endOperation(for: .claude, id: operationID) }
    guard let snapshot = await awaitOperation(for: .claude, id: operationID, {
      await self.service.claude.fetchSnapshot(context: .init())
    }) else { return }
    guard generation == sessionGeneration(for: .claude) else { return }
    apply(snapshot)
  }

  func prepareClaudeConnect() {
    do {
      guard let bundledHelper = Bundle.main.url(
        forAuxiliaryExecutable: "dashis-claude-statusline"
      ) else {
        throw ClaudeSettingsPatchError.helperUnavailable
      }
      try ClaudeBridgeInstaller.validateBundledHelper(at: bundledHelper)
      let patch = try ClaudeSettingsPatcher.prepareConnect(
        helperURL: ClaudeBridgeInstaller.defaultInstalledHelperURL,
        requireExistingHelper: false
      )
      claudePendingBundledHelper = bundledHelper
      claudePendingPatch = patch
      claudePatchSummary = patch.summary
      claudeConnectionMessage = "Review the settings change, then apply it."
    } catch {
      claudePendingBundledHelper = nil
      claudePendingPatch = nil
      claudePatchSummary = nil
      claudeConnectionMessage = ProviderJSON.safeMessage(error)
    }
  }

  func prepareClaudeDisconnect() {
    do {
      let patch = try ClaudeSettingsPatcher.prepareDisconnect()
      claudePendingBundledHelper = nil
      claudePendingPatch = patch
      claudePatchSummary = patch.summary
      claudeConnectionMessage = "Review the restore change, then apply it."
    } catch {
      claudePendingBundledHelper = nil
      claudePendingPatch = nil
      claudePatchSummary = nil
      claudeConnectionMessage = ProviderJSON.safeMessage(error)
    }
  }

  func applyClaudePendingPatch() {
    guard let patch = claudePendingPatch else { return }
    do {
      if patch.kind == .connect {
        guard let bundledHelper = claudePendingBundledHelper else {
          throw ClaudeSettingsPatchError.helperUnavailable
        }
        _ = try ClaudeBridgeInstaller.installHelper(from: bundledHelper)
      }
      try ClaudeSettingsPatcher.apply(patch)
      var snapshotRemovalWarning: String?
      if patch.kind == .disconnect {
        invalidateSession(for: .claude)
        do {
          try ClaudeSnapshotFile.remove()
        } catch {
          snapshotRemovalWarning = ProviderJSON.safeMessage(error)
        }
        clearSnapshot(
          for: .claude,
          base: .claude,
          message: "Claude bridge disconnected; use Preview connect to enable it again."
        )
      }
      if let snapshotRemovalWarning {
        claudeConnectionMessage = "Bridge disconnected, but the sanitized snapshot could not be removed: \(snapshotRemovalWarning)"
      } else {
        claudeConnectionMessage = patch.kind == .connect
          ? "Bridge connected. Use Claude Code once, then reload the snapshot."
          : "Bridge disconnected and the prior status line was restored."
      }
      claudePendingPatch = nil
      claudePendingBundledHelper = nil
      claudePatchSummary = nil
    } catch {
      claudeConnectionMessage = ProviderJSON.safeMessage(error)
    }
  }

  func cancelClaudePendingPatch() {
    claudePendingBundledHelper = nil
    claudePendingPatch = nil
    claudePatchSummary = nil
    claudeConnectionMessage = "Settings change cancelled."
  }

  func clearClaudeLoadedSnapshot() {
    invalidateSession(for: .claude)
    claudePendingPatch = nil
    claudePendingBundledHelper = nil
    claudePatchSummary = nil
    do {
      try ClaudeSnapshotFile.remove()
      claudeConnectionMessage = "Sanitized Claude snapshot removed; bridge configuration was not changed."
    } catch {
      claudeConnectionMessage = ProviderJSON.safeMessage(error)
    }
    clearSnapshot(
      for: .claude,
      base: .claude,
      message: "Claude snapshot cleared; bridge configuration was not changed."
    )
  }

  func recordGoogleManualReading() async {
    invalidateSession(for: .google)
    let generation = sessionGeneration(for: .google)
    let fields = [googleManualUsed, googleManualLimit, googleManualRemaining]
    let values = fields.map(parseOptionalDouble)
    guard zip(fields, values).allSatisfy({ pair in
      pair.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pair.1 != nil
    }) else {
      applyError(
        providerID: .google,
        scope: ProviderScope(kind: .manual, label: "Google AI subscription"),
        source: .manualOnly,
        operation: "google.consumer.input",
        message: "Manual quota values must be numbers or left blank."
      )
      return
    }
    let unit = googleManualUnit.trimmingCharacters(in: .whitespacesAndNewlines)
    let snapshot = await service.googleConsumer.fetchSnapshot(context: GoogleConsumerManualContext(
      observedAt: Date(),
      used: values[0],
      limit: values[1],
      remaining: values[2],
      unit: unit.isEmpty ? "%" : String(unit.prefix(32))
    ))
    guard generation == sessionGeneration(for: .google) else { return }
    apply(snapshot)
  }

  func openGoogleConsumerQuotaPage() {
    guard let url = URL(string: "https://gemini.google.com/app") else { return }
    NSWorkspace.shared.open(url)
  }

  func connectGoogleProject() async {
    let clientID = googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientID.isEmpty else {
      invalidateSession(for: .google)
      googleConnectionMessage = "Enter a Google Desktop OAuth client ID."
      return
    }
    let operationID = beginOperation(for: .google)
    defer { endOperation(for: .google, id: operationID) }
    let generation = sessionGeneration(for: .google)
    let connection = await awaitOperation(for: .google, id: operationID, {
      await captureProviderResult {
        try await self.service.googleConnections.connectGoogle(clientID: clientID)
      }
    })
    guard let connection else { return }
    switch connection {
    case .success(let accessToken):
      guard generation == sessionGeneration(for: .google) else { return }
      googleAccessToken = accessToken
      googleConnectionMessage = "Connected for this app session."
      await checkGoogleProject(
        setLoadingState: false,
        expectedOperationID: operationID,
        expectedGeneration: generation
      )
    case .failure(let error):
      guard generation == sessionGeneration(for: .google) else { return }
      googleAccessToken = nil
      googleConnectionMessage = ProviderJSON.safeMessage(error)
    }
  }

  func checkGoogleProject() async {
    await checkGoogleProject(setLoadingState: true)
  }

  private func checkGoogleProject(
    setLoadingState: Bool,
    expectedOperationID: UUID? = nil,
    expectedGeneration: Int? = nil
  ) async {
    if let expectedOperationID, let expectedGeneration {
      guard activeOperationIDs[.google] == expectedOperationID,
            sessionGeneration(for: .google) == expectedGeneration
      else { return }
    }
    let projectID = googleProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let accessToken = googleAccessToken else {
      if setLoadingState { invalidateSession(for: .google) }
      applyError(
        providerID: .google,
        scope: .project(projectID.isEmpty ? "Google Cloud project" : projectID),
        source: .officialDerived,
        operation: "google.oauth",
        message: "Connect Google for this app session before checking project quota."
      )
      return
    }
    guard accessToken.isUsable() else {
      if setLoadingState { invalidateSession(for: .google) }
      googleAccessToken = nil
      googleConnectionMessage = "The Google access token expired. Connect Google again."
      applyError(
        providerID: .google,
        scope: .project(projectID.isEmpty ? "Google Cloud project" : projectID),
        source: .officialDerived,
        operation: "google.oauth.expired",
        message: googleConnectionMessage
      )
      return
    }
    guard !projectID.isEmpty else {
      if setLoadingState { invalidateSession(for: .google) }
      applyError(
        providerID: .google,
        scope: .project("Google Cloud project"),
        source: .officialDerived,
        operation: "google.project.input",
        message: "Enter a Google Cloud project ID or project number."
      )
      return
    }

    let quotaIDTokens = googleQuotaIDs
      .components(separatedBy: CharacterSet(charactersIn: ",\n\t "))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard quotaIDTokens.allSatisfy(GoogleQuotaValidation.validQuotaID) else {
      if setLoadingState { invalidateSession(for: .google) }
      applyError(
        providerID: .google,
        scope: .project(projectID),
        source: .officialDerived,
        operation: "google.quota-selection.input",
        message: "Quota IDs contain unsupported characters."
      )
      return
    }
    let selectedQuotaIDs = quotaIDTokens.isEmpty ? nil : Set(quotaIDTokens)

    let operationID = setLoadingState
      ? beginOperation(for: .google)
      : (expectedOperationID ?? activeOperationIDs[.google])
    guard let operationID else { return }
    defer {
      if setLoadingState { endOperation(for: .google, id: operationID) }
    }
    let generation = sessionGeneration(for: .google)
    guard let snapshot = await awaitOperation(for: .google, id: operationID, {
      await self.service.googleProject.fetchSnapshot(context: GeminiAPIProjectContext(
        projectID: projectID,
        accessToken: accessToken,
        selectedQuotaIDs: selectedQuotaIDs
      ))
    }) else { return }
    guard generation == sessionGeneration(for: .google) else { return }
    apply(snapshot)
  }

  func clearGoogleSession() {
    invalidateSession(for: .google)
    service.googleConnections.cancelActiveConnections()
    googleAccessToken = nil
    googleOAuthClientID = ""
    googleProjectID = ""
    googleQuotaIDs = ""
    googleManualUsed = ""
    googleManualLimit = ""
    googleManualRemaining = ""
    googleManualUnit = "%"
    googleMode = .consumer
    googleConnectionMessage = "Not connected"
    clearSnapshot(for: .google, base: .googleAI, message: "Google inputs, OAuth state, token, and snapshot cleared from memory.")
  }

  func connectOpenRouterOAuth() async {
    let operationID = beginOperation(for: .openRouter)
    let generation = sessionGeneration(for: .openRouter)
    defer { endOperation(for: .openRouter, id: operationID) }
    let connection = await awaitOperation(for: .openRouter, id: operationID, {
      await captureProviderResult {
        try await self.service.openRouterConnections.connectOpenRouter()
      }
    })
    guard let connection else { return }
    switch connection {
    case .success(let apiKey):
      guard generation == sessionGeneration(for: .openRouter) else { return }
      openRouterOAuthAPIKey = apiKey
      openRouterConnectionMessage = "Connected for this app session."
      guard let snapshot = await awaitOperation(for: .openRouter, id: operationID, {
        await self.service.openRouter.fetchAPIKeySnapshot(apiKey: apiKey)
      }) else { return }
      guard generation == sessionGeneration(for: .openRouter) else { return }
      apply(snapshot)
    case .failure(let error):
      guard generation == sessionGeneration(for: .openRouter) else { return }
      openRouterOAuthAPIKey = nil
      openRouterConnectionMessage = ProviderJSON.safeMessage(error)
      applyError(
        providerID: .openRouter,
        scope: ProviderScope(kind: .apiKey, label: "OpenRouter OAuth key"),
        source: .officialDirect,
        operation: "openrouter.oauth",
        message: ProviderJSON.safeMessage(error)
      )
    }
  }

  func checkOpenRouterOAuthKey() async {
    guard let key = openRouterOAuthAPIKey else {
      invalidateSession(for: .openRouter)
      openRouterConnectionMessage = "Connect OpenRouter first."
      return
    }
    let operationID = beginOperation(for: .openRouter)
    defer { endOperation(for: .openRouter, id: operationID) }
    let generation = sessionGeneration(for: .openRouter)
    guard let snapshot = await awaitOperation(for: .openRouter, id: operationID, {
      await self.service.openRouter.fetchAPIKeySnapshot(apiKey: key)
    }) else { return }
    guard generation == sessionGeneration(for: .openRouter) else { return }
    if snapshot.warnings.contains(where: { $0.id == "openrouter-key-expired" })
      || snapshot.partialFailures.contains(where: {
        $0.message.contains("HTTP 401") || $0.message.contains("HTTP 403")
      }) {
      openRouterOAuthAPIKey = nil
      openRouterConnectionMessage = "The OpenRouter key expired or was rejected. Connect again."
    }
    apply(snapshot)
  }

  func checkOpenRouterManagement() async {
    let apiKey = openRouterManagementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
      invalidateSession(for: .openRouter)
      applyError(
        providerID: .openRouter,
        scope: .workspace("OpenRouter account"),
        source: .officialDirect,
        operation: "openrouter.management.input",
        message: "Enter an OpenRouter management key for the advanced check."
      )
      return
    }
    let operationID = beginOperation(for: .openRouter)
    defer { endOperation(for: .openRouter, id: operationID) }
    let generation = sessionGeneration(for: .openRouter)
    let generationID = openRouterGenerationID
    let analyticsDays = openRouterAnalyticsDays
    guard let snapshot = await awaitOperation(for: .openRouter, id: operationID, {
      await self.service.openRouter.fetchManagementSnapshot(context: .init(
        apiKey: apiKey,
        generationID: generationID,
        analyticsDays: analyticsDays
      ))
    }) else { return }
    guard generation == sessionGeneration(for: .openRouter) else { return }
    apply(snapshot)
  }

  func clearOpenRouterSession() {
    invalidateSession(for: .openRouter)
    service.openRouterConnections.cancelActiveConnections()
    openRouterOAuthAPIKey = nil
    openRouterManagementAPIKey = ""
    openRouterGenerationID = ""
    openRouterAnalyticsDays = 30
    openRouterMode = .oauthKey
    openRouterConnectionMessage = "Not connected"
    clearSnapshot(
      for: .openRouter,
      base: .openRouter,
      message: "OpenRouter keys, OAuth state, verifier, listener, and snapshot cleared from memory."
    )
  }

  private func apply(_ snapshot: ProviderSnapshot) {
    snapshots[snapshot.providerID] = snapshot
    guard let index = providers.firstIndex(where: { $0.id == snapshot.providerID.rawValue }) else { return }
    var projected = ProviderCardProjection.apply(
      snapshot: snapshot,
      to: baseProvider(for: snapshot.providerID)
    )
    projected.actionTitle = primaryActionTitle(for: snapshot.providerID)
    providers[index] = projected
  }

  private func applyError(
    providerID: ProviderID,
    scope: ProviderScope,
    source: UsageSourceKind,
    operation: String,
    message: String
  ) {
    apply(ProviderSnapshot(
      providerID: providerID,
      scope: scope,
      sourceKind: source,
      observedAt: Date(),
      windows: [],
      balance: nil,
      metrics: [],
      warnings: [],
      partialFailures: [ProviderFailure(operation: operation, message: message)]
    ))
  }

  private func clearSnapshot(for providerID: ProviderID, base: DashisProvider, message: String) {
    snapshots.removeValue(forKey: providerID)
    guard let index = providers.firstIndex(where: { $0.id == providerID.rawValue }) else { return }
    var reset = base
    reset.caption = message
    reset.actionTitle = primaryActionTitle(for: providerID)
    providers[index] = reset
  }

  private func baseProvider(for providerID: ProviderID) -> DashisProvider {
    switch providerID {
    case .codex: .codex
    case .claude: .claude
    case .google: .googleAI
    case .openRouter: .openRouter
    default:
      provider(id: providerID.rawValue) ?? .custom(name: providerID.rawValue, kind: "Native adapter")
    }
  }

  private func primaryActionTitle(for providerID: ProviderID) -> String? {
    switch providerID {
    case .codex:
      "Check Codex"
    case .claude:
      "Reload snapshot"
    case .google:
      googleMode == .consumer ? "Open official page" : "Check project quotas"
    case .openRouter:
      openRouterMode == .management
        ? "Check management data"
        : (isOpenRouterOAuthConnected ? "Check key limit" : "Connect OpenRouter")
    default:
      nil
    }
  }

  private func refreshPrimaryAction(for providerID: ProviderID) {
    guard let index = providers.firstIndex(where: { $0.id == providerID.rawValue }) else { return }
    providers[index].actionTitle = primaryActionTitle(for: providerID)
  }

  private func sessionGeneration(for providerID: ProviderID) -> Int {
    sessionGenerations[providerID, default: 0]
  }

  private func beginOperation(for providerID: ProviderID) -> UUID {
    activeOperationCancellations.removeValue(forKey: providerID)?.cancel()
    sessionGenerations[providerID, default: 0] += 1
    let operationID = UUID()
    activeOperationIDs[providerID] = operationID
    loadingProviderIDs.insert(providerID.rawValue)
    return operationID
  }

  private func endOperation(for providerID: ProviderID, id: UUID) {
    guard activeOperationIDs[providerID] == id else { return }
    if activeOperationCancellations[providerID]?.id == id {
      activeOperationCancellations.removeValue(forKey: providerID)
    }
    activeOperationIDs.removeValue(forKey: providerID)
    loadingProviderIDs.remove(providerID.rawValue)
  }

  private func invalidateSession(for providerID: ProviderID) {
    activeOperationCancellations.removeValue(forKey: providerID)?.cancel()
    sessionGenerations[providerID, default: 0] += 1
    activeOperationIDs.removeValue(forKey: providerID)
    loadingProviderIDs.remove(providerID.rawValue)
  }

  private func awaitOperation<Value: Sendable>(
    for providerID: ProviderID,
    id: UUID,
    _ operation: @escaping @MainActor () async -> Value
  ) async -> Value? {
    guard activeOperationIDs[providerID] == id else { return nil }
    let task = Task { @MainActor in await operation() }
    activeOperationCancellations[providerID] = (id, { task.cancel() })
    let value = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    guard !Task.isCancelled, activeOperationIDs[providerID] == id else { return nil }
    return value
  }

  private func handleGoogleModeChange() {
    invalidateSession(for: .google)
    service.googleConnections.cancelActiveConnections()
    googleAccessToken = nil
    googleConnectionMessage = "Not connected"
    if googleMode == .consumer {
      googleOAuthClientID = ""
      googleProjectID = ""
      googleQuotaIDs = ""
    } else {
      googleManualUsed = ""
      googleManualLimit = ""
      googleManualRemaining = ""
      googleManualUnit = "%"
    }
    var base = DashisProvider.googleAI
    if googleMode == .cloudProject {
      base.kind = "Gemini API project"
      base.primary = "Not connected"
      base.caption = "Connect a Google Cloud project to derive quota from Cloud Quotas and Cloud Monitoring."
      base.statusLabel = "not connected"
      base.sourceLabel = UsageSourceKind.officialDerived.label
      base.actionTitle = "Check project quotas"
    }
    clearSnapshot(
      for: .google,
      base: base,
      message: googleMode == .consumer
        ? "Consumer subscription quota requires an official manual check."
        : "Project mode selected; connect Google for this app session."
    )
  }

  private func handleOpenRouterModeChange() {
    invalidateSession(for: .openRouter)
    service.openRouterConnections.cancelActiveConnections()
    openRouterOAuthAPIKey = nil
    openRouterManagementAPIKey = ""
    openRouterGenerationID = ""
    openRouterConnectionMessage = "Not connected"
    clearSnapshot(
      for: .openRouter,
      base: .openRouter,
      message: openRouterMode == .oauthKey
        ? "OAuth key mode selected; connect OpenRouter for this app session."
        : "Management mode selected; enter a temporary management key."
    )
  }

  private func parseOptionalDouble(_ raw: String) -> Double? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, let number = Double(value), number.isFinite else { return nil }
    return number
  }
}
