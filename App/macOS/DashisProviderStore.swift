import AppKit
import DashisCollectorContract
import Foundation

enum DashisOpenRouterMode: String, CaseIterable, Identifiable {
  case account = "Account"
  case singleKey = "Single key"

  var id: String { rawValue }
}

enum DashisGoogleMode: String, CaseIterable, Identifiable {
  case consumer = "Consumer subscription"
  case cloudProject = "Gemini API project"

  var id: String { rawValue }
}

enum DashisProviderVisibilityPreferences {
  static let hiddenProviderIDsKey = "dashis.hiddenProviderIDs"

  static func load(
    from defaults: UserDefaults,
    validProviderIDs: Set<String>
  ) -> Set<String> {
    Set(defaults.stringArray(forKey: hiddenProviderIDsKey) ?? [])
      .intersection(validProviderIDs)
  }

  static func save(_ hiddenProviderIDs: Set<String>, to defaults: UserDefaults) {
    if hiddenProviderIDs.isEmpty {
      defaults.removeObject(forKey: hiddenProviderIDsKey)
    } else {
      defaults.set(hiddenProviderIDs.sorted(), forKey: hiddenProviderIDsKey)
    }
  }
}

@MainActor
final class DashisProviderStore: ObservableObject {
  @Published private(set) var providers: [DashisProvider] = DashisProviderCatalog.providers
  @Published private(set) var hiddenProviderIDs: Set<String>
  @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
  @Published private(set) var observations: [CollectionTargetKey: ProviderObservation] = [:]
  @Published private var loadingProviderIDs: Set<String> = []
  @Published private var collectorRouteSelections: [String: String] = [:]
  @Published private var collectorInputValues: [String: [String: String]] = [:]

  @Published var codexWorkspaceID = ""
  @Published var codexAnalyticsAPIKey = ""
  @Published var codexAnalyticsDays = 30

  @Published var openRouterMode: DashisOpenRouterMode = .account {
    didSet {
      guard oldValue != openRouterMode else { return }
      handleOpenRouterModeChange()
    }
  }
  @Published var openRouterManagementAPIKey = "" {
    didSet {
      guard oldValue != openRouterManagementAPIKey, openRouterMode == .account else { return }
      invalidateSession(for: .openRouter)
      openRouterRecentCallsState = .idle
      if snapshots[.openRouter] != nil {
        clearSnapshot(
          for: .openRouter,
          base: .openRouter,
          message: "Management key changed; check the account again before loading data."
        )
      }
      refreshPrimaryAction(for: .openRouter)
    }
  }
  @Published var openRouterGenerationID = ""
  @Published var openRouterAnalyticsDays = 30
  @Published var openRouterRecentCallsDays = 1 {
    didSet {
      guard oldValue != openRouterRecentCallsDays else { return }
      if case .loading = openRouterRecentCallsState {
        invalidateSession(for: .openRouter)
      }
      openRouterRecentCallsState = .idle
    }
  }
  @Published private(set) var openRouterRecentCallsState: OpenRouterRecentCallsState = .idle
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
  private let visibilityDefaults: UserDefaults
  private var sessionGenerations: [ProviderID: Int] = [:]
  private var activeOperationIDs: [ProviderID: UUID] = [:]
  private var activeOperationCancellations: [ProviderID: (id: UUID, cancel: () -> Void)] = [:]

  init(
    service: DashisProviderService = DashisProviderService(),
    visibilityDefaults: UserDefaults = .standard
  ) {
    self.service = service
    self.visibilityDefaults = visibilityDefaults
    hiddenProviderIDs = DashisProviderVisibilityPreferences.load(
      from: visibilityDefaults,
      validProviderIDs: Set(DashisProviderCatalog.providers.map(\.id))
    )
    collectorRouteSelections = Dictionary(uniqueKeysWithValues:
      CollectorLiveRouteCatalog.providerIDs.compactMap { providerID in
        DashisProviderCatalog.defaultLiveRoute(
          for: providerID.rawValue).map {
            (providerID.rawValue, $0.id)
          }
      })
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
          id: "visual-qa-five-hour",
          label: "5-hour window",
          used: 12,
          limit: 100,
          remaining: 88,
          usedPercentage: 12,
          remainingPercentage: 88,
          resetsAt: now.addingTimeInterval(5 * 60 * 60),
          unit: "%",
          isEstimated: false
        ),
        QuotaWindow(
          id: "visual-qa-seven-day",
          label: "7-day window",
          used: 6,
          limit: 100,
          remaining: 94,
          usedPercentage: 6,
          remainingPercentage: 94,
          resetsAt: now.addingTimeInterval(7 * 24 * 60 * 60),
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

  var needsOpenRouterAccountSetup: Bool {
    openRouterMode == .account
      && openRouterManagementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var canLoadOpenRouterRecentCalls: Bool {
    guard openRouterMode == .account,
          !needsOpenRouterAccountSetup,
          let snapshot = snapshots[.openRouter]
    else {
      return false
    }
    return snapshot.scope == .workspace("OpenRouter account") && snapshot.hasData
  }

  var isGoogleProjectConnected: Bool {
    guard let token = googleAccessToken else { return false }
    return token.isUsable()
  }

  var hasClaudePendingPatch: Bool {
    claudePendingPatch != nil
  }

  var visibleProviders: [DashisProvider] {
    providers.filter { !hiddenProviderIDs.contains($0.id) }
  }

  func provider(id: String) -> DashisProvider? {
    providers.first { $0.id == id }
  }

  func isProviderVisible(_ providerID: String) -> Bool {
    provider(id: providerID) != nil && !hiddenProviderIDs.contains(providerID)
  }

  func setProviderVisible(_ isVisible: Bool, for providerID: String) {
    guard provider(id: providerID) != nil else { return }

    var nextHiddenProviderIDs = hiddenProviderIDs
    if isVisible {
      nextHiddenProviderIDs.remove(providerID)
    } else {
      nextHiddenProviderIDs.insert(providerID)
    }

    guard nextHiddenProviderIDs != hiddenProviderIDs else { return }
    hiddenProviderIDs = nextHiddenProviderIDs
    DashisProviderVisibilityPreferences.save(
      nextHiddenProviderIDs,
      to: visibilityDefaults
    )
  }

  func normalizedDisplaySelection(_ selectionID: String) -> String {
    let normalizedSelection = DashisSelection.normalizedRootSelection(selectionID)
    if normalizedSelection == DashisSelection.dashboard
        || normalizedSelection == DashisSelection.settings {
      return normalizedSelection
    }
    guard isProviderVisible(normalizedSelection) else {
      return DashisSelection.dashboard
    }
    return normalizedSelection
  }

  func title(for selectionID: String) -> String {
    if selectionID == DashisSelection.dashboard { return "Dashboard" }
    if selectionID == DashisSelection.providers { return "Providers" }
    if selectionID == DashisSelection.settings { return "Settings" }
    return provider(id: selectionID)?.name ?? "Dashboard"
  }

  func isLoading(_ providerID: String) -> Bool {
    loadingProviderIDs.contains(providerID)
  }

  func collectorRoutes(for providerID: String) -> [CollectorLiveRouteDefinition] {
    DashisProviderCatalog.liveRoutes(for: providerID)
  }

  func selectedCollectorRoute(
    for providerID: String
  ) -> CollectorLiveRouteDefinition? {
    let routes = collectorRoutes(for: providerID)
    guard let selectedID = collectorRouteSelections[providerID] else {
      return DashisProviderCatalog.defaultLiveRoute(for: providerID)
    }
    return routes.first { $0.id == selectedID }
      ?? DashisProviderCatalog.defaultLiveRoute(for: providerID)
  }

  func selectCollectorRoute(_ routeID: String, for providerID: String) {
    guard collectorRoutes(for: providerID).contains(where: { $0.id == routeID }),
          collectorRouteSelections[providerID] != routeID
    else {
      return
    }
    let providerKey = ProviderID(rawValue: providerID)
    let target = collectorTarget(for: providerID)
    invalidateSession(for: providerKey)
    collectorRouteSelections[providerID] = routeID
    snapshots.removeValue(forKey: providerKey)
    observations.removeValue(forKey: target)
    providers = providers.map { provider in
      guard provider.id == providerID else { return provider }
      return DashisProviderCatalog.providers.first {
        $0.id == providerID
      } ?? provider
    }
    Task {
      await service.collectionRuntime.invalidate(target)
    }
  }

  func collectorInputValue(routeID: String, key: String) -> String {
    collectorInputValues[routeID]?[key] ?? ""
  }

  func setCollectorInputValue(
    _ value: String,
    routeID: String,
    key: String
  ) {
    guard CollectorLiveRouteCatalog.route(id: routeID)?
      .allowedConfigurationKeys.contains(key) == true
    else {
      return
    }
    collectorInputValues[routeID, default: [:]][key] = value
  }

  func hasCollectorSessionState(for providerID: String) -> Bool {
    let providerKey = ProviderID(rawValue: providerID)
    return snapshots[providerKey] != nil
      || observations[collectorTarget(for: providerID)] != nil
      || collectorRoutes(for: providerID).contains {
        collectorInputValues[$0.id]?.values.contains(where: { !$0.isEmpty }) == true
      }
      || isLoading(providerID)
  }

  func clearCollectorSession(for providerID: String) {
    let providerKey = ProviderID(rawValue: providerID)
    invalidateSession(for: providerKey)
    for route in collectorRoutes(for: providerID) {
      collectorInputValues.removeValue(forKey: route.id)
    }
    let target = collectorTarget(for: providerID)
    observations.removeValue(forKey: target)
    Task {
      await service.collectionRuntime.invalidate(target)
    }
    let base = DashisProviderCatalog.providers.first {
      $0.id == providerID
    } ?? .custom(name: providerID, kind: "Collector adapter")
    clearSnapshot(
      for: providerKey,
      base: base,
      message: "Temporary collector inputs and the loaded snapshot were removed from this Dashis session.")
  }

  func runCollectorCheck(
    for providerID: String,
    consentGranted: Bool
  ) async {
    guard provider(id: providerID)?.integration == .collector,
          let route = selectedCollectorRoute(for: providerID)
    else {
      return
    }
    let providerKey = ProviderID(rawValue: providerID)
    guard !route.requiresConsent || consentGranted else {
      applyError(
        providerID: providerKey,
        scope: .personal("Current session"),
        source: .experimentalPrivate,
        operation: "collector.consent",
        message: "Confirm this collection method before running it.")
      return
    }

    let values = collectorInputValues[route.id] ?? [:]
    if let missing = route.configurationFields.first(where: {
      $0.required
        && (values[$0.key] ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      applyError(
        providerID: providerKey,
        scope: .personal("Current session"),
        source: .experimentalPrivate,
        operation: "collector.input",
        message: "Enter \(missing.label) for this collection method.")
      return
    }
    let environment = values.filter {
      route.allowedConfigurationKeys.contains($0.key)
        && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    let target = collectorTarget(for: providerID)
    let operationID = beginOperation(for: providerKey)
    let generation = sessionGeneration(for: providerKey)
    defer { endOperation(for: providerKey, id: operationID) }
    guard let result = await awaitOperation(for: providerKey, id: operationID, {
      await self.service.collectionRuntime.run(ProviderCollectionCommand(
        target: target,
        routeID: route.id,
        interaction: .userInitiated,
        budgetMilliseconds: 60_000,
        collectorEnvironment: environment,
        collectorConsentGranted: consentGranted))
    }) else {
      return
    }
    guard generation == sessionGeneration(for: providerKey) else { return }
    switch result {
    case let .completed(observation):
      observations[target] = observation
      apply(ProviderObservationSnapshotProjection.make(
        observation,
        providerID: providerKey))
    case .superseded:
      break
    case .cancelled:
      applyError(
        providerID: providerKey,
        scope: .personal("Current session"),
        source: .experimentalPrivate,
        operation: "collector.cancelled",
        message: "The collection was cancelled.")
    case let .failed(code):
      applyError(
        providerID: providerKey,
        scope: .personal("Current session"),
        source: .experimentalPrivate,
        operation: route.strategyID,
        message: collectorFailureMessage(code))
    }
  }

  func runPrimaryCheck(for providerID: String) async {
    guard let integration = provider(id: providerID)?.integration else { return }
    if integration == .collector {
      await runCollectorCheck(for: providerID, consentGranted: false)
      return
    }
    guard integration == .native else { return }
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
      if openRouterMode == .account {
        await checkOpenRouterAccount()
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

  func checkOpenRouterAccount() async {
    let apiKey = openRouterManagementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
      invalidateSession(for: .openRouter)
      applyError(
        providerID: .openRouter,
        scope: .workspace("OpenRouter account"),
        source: .officialDirect,
        operation: "openrouter.management.input",
        message: "Enter an OpenRouter management key to check the whole account."
      )
      return
    }
    if case .loading = openRouterRecentCallsState {
      openRouterRecentCallsState = .idle
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

  func loadOpenRouterRecentCalls() async {
    let apiKey = openRouterManagementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
      openRouterRecentCallsState = .failed(
        "Enter a management key and check the whole account first."
      )
      return
    }
    guard canLoadOpenRouterRecentCalls else {
      openRouterRecentCallsState = .failed(
        "Check the whole account successfully before loading call metadata."
      )
      return
    }

    openRouterRecentCallsState = .loading
    let operationID = beginOperation(for: .openRouter)
    defer { endOperation(for: .openRouter, id: operationID) }
    let generation = sessionGeneration(for: .openRouter)
    let days = openRouterRecentCallsDays
    guard let result = await awaitOperation(for: .openRouter, id: operationID, {
      await captureProviderResult {
        try await self.service.openRouter.fetchRecentCalls(
          apiKey: apiKey,
          days: days,
          limit: 20
        )
      }
    }) else { return }
    guard generation == sessionGeneration(for: .openRouter) else { return }
    switch result {
    case .success(let page):
      openRouterRecentCallsState = .loaded(page)
    case .failure(let error):
      openRouterRecentCallsState = .failed(ProviderJSON.safeMessage(error))
    }
  }

  func clearOpenRouterSession() {
    invalidateSession(for: .openRouter)
    service.openRouterConnections.cancelActiveConnections()
    openRouterOAuthAPIKey = nil
    openRouterManagementAPIKey = ""
    openRouterGenerationID = ""
    openRouterAnalyticsDays = 30
    openRouterRecentCallsDays = 1
    openRouterRecentCallsState = .idle
    openRouterMode = .account
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
      openRouterMode == .account
        ? (needsOpenRouterAccountSetup ? "Set up account" : "Check whole account")
        : (isOpenRouterOAuthConnected ? "Check key limit" : "Connect OpenRouter")
    default:
      provider(id: providerID.rawValue)?.integration == .collector
        ? "Configure"
        : nil
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
    openRouterRecentCallsDays = 1
    openRouterRecentCallsState = .idle
    openRouterConnectionMessage = "Not connected"
    clearSnapshot(
      for: .openRouter,
      base: .openRouter,
      message: openRouterMode == .account
        ? "Account mode selected; enter a temporary management key."
        : "Single-key mode selected; connect OpenRouter for this app session."
    )
  }

  private func parseOptionalDouble(_ raw: String) -> Double? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, let number = Double(value), number.isFinite else { return nil }
    return number
  }

  private func collectorTarget(for providerID: String) -> CollectionTargetKey {
    CollectionTargetKey(
      productID: ProviderProductID(rawValue: "collector.\(providerID)"),
      accountSlot: .ambient("local-session"),
      scopeKind: "usage",
      scopeID: ProviderScopeID(rawValue: providerID))
  }

  private func collectorFailureMessage(_ code: String) -> String {
    if code.contains("worker_transport_failure") {
      return "The collector worker is unavailable. Rebuild and relaunch Dashis, then try again."
    }
    if code.contains("route_consent_required") {
      return "This collection method requires confirmation for each run."
    }
    if code.contains("configuration_lease") {
      return "The temporary configuration lease was rejected before collection started."
    }
    if code.contains("no_allowed_available_strategy") {
      return "The selected CodexBar method could not find the required local sign-in or configuration."
    }
    if code.contains("fetch_failed") || code.contains("providerFailure") {
      return "CodexBar reached the selected adapter, but the provider check failed. Verify the local sign-in or temporary fields."
    }
    if code.contains("deadline") {
      return "The provider check exceeded its 60-second deadline."
    }
    return "The collector check failed safely (\(code))."
  }
}
