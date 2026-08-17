import DashisCollectorContract
import SwiftUI

private enum DashisProviderDetailLayout {
  static let contentWidth: CGFloat = 900
  static let fieldWidth: CGFloat = 420
  static let pickerWidth: CGFloat = 300
}

private struct DashisFormPrimaryAction: View {
  let title: String
  let loadingTitle: String
  let isLoading: Bool
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    HStack {
      Spacer()
      Button(action: action) {
        HStack(spacing: 7) {
          if isLoading {
            ProgressView()
              .controlSize(.small)
              .accessibilityHidden(true)
          }
          Text(isLoading ? loadingTitle : title)
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(isLoading || isDisabled)
    }
  }
}

struct DashisProviderCard: View {
  let provider: DashisProvider
  let snapshot: ProviderSnapshot?
  let onOpen: () -> Void

  var body: some View {
    Button(action: onOpen) {
      GroupBox {
        VStack(alignment: .leading, spacing: 0) {
          dashboardHeader

          Divider()
            .padding(.vertical, 12)

          if let visualization, !visualization.primaryCards.isEmpty {
            dashboardPrimaryUsage(visualization.primaryCards)
          } else {
            dashboardEmptyState
          }
        }
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .padding(.vertical, 2)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(provider.name)
    .accessibilityValue(accessibilityValue)
    .accessibilityHint("Show usage details")
    .accessibilityCustomContent("Provider type", provider.kind)
    .accessibilityCustomContent("Source", provider.sourceLabel)
    .accessibilityCustomContent("Freshness", provider.freshnessLabel)
    .accessibilityCustomContent("Status", provider.statusLabel)
  }

  private var visualization: ProviderVisualization? {
    snapshot.map { ProviderVisualizationProjection.make(snapshot: $0) }
  }

  private var dashboardHeader: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(provider.name)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(1)

      Spacer(minLength: 12)

      if let qualifier = provider.summaryQualifier {
        DashisProviderQualifier(provider: provider, label: qualifier)
      }
    }
  }

  @ViewBuilder
  private func dashboardPrimaryUsage(_ cards: [ProviderUsageCard]) -> some View {
    if cards.count > 1 {
      HStack(alignment: .top, spacing: 16) {
        DashisDashboardUsageMetric(card: cards[0])
        Divider()
        DashisDashboardUsageMetric(card: cards[1])
      }
    } else if let card = cards.first {
      DashisDashboardUsageMetric(card: card)
    }
  }

  private var dashboardEmptyState: some View {
    Text(provider.primary)
      .font(.title2.weight(.semibold))
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .minimumScaleFactor(0.82)
      .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
  }

  private var accessibilityValue: String {
    guard let primaryCards = visualization?.primaryCards, !primaryCards.isEmpty else {
      return provider.primary
    }
    return primaryCards.map { card in
      [card.title, card.headline, card.descriptor]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
    .joined(separator: ". ")
  }
}

private struct DashisDashboardUsageMetric: View {
  let card: ProviderUsageCard

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(card.title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)

        Spacer(minLength: 6)

        if let statusLabel = card.statusLabel {
          Text(statusLabel)
            .font(.caption2.weight(.medium))
            .foregroundStyle(DashisTheme.statusColor(card.tone))
            .lineLimit(1)
        }
      }

      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(card.headline)
          .font(.title2.weight(.semibold))
          .monospacedDigit()

        if !card.descriptor.isEmpty {
          Text(card.descriptor)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.72)

      if let progress = card.progressFraction {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .tint(DashisUsageProgressStyle.color(for: card, progress: progress))
          .accessibilityLabel(card.title)
      }

      if let supportingText = card.supportingText {
        Text(supportingText)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
  }
}

private struct DashisProviderQualifier: View {
  let provider: DashisProvider
  let label: String

  var body: some View {
    Text(label)
      .font(.caption.weight(.medium))
      .foregroundStyle(DashisTheme.statusColor(provider.tone))
      .accessibilityHidden(true)
  }
}

struct DashisProviderDetail: View {
  let provider: DashisProvider
  @ObservedObject var store: DashisProviderStore

  var body: some View {
    ScrollView {
      DashisProviderMainCard(
        provider: provider,
        snapshot: snapshot,
        visualization: visualization
      )
      .frame(maxWidth: DashisProviderDetailLayout.contentWidth)
      .padding(.horizontal, 28)
      .padding(.vertical, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var snapshot: ProviderSnapshot? {
    store.snapshots[ProviderID(rawValue: provider.id)]
  }

  private var visualization: ProviderVisualization? {
    snapshot.map { ProviderVisualizationProjection.make(snapshot: $0) }
  }
}

struct DashisProviderSettingsDetail: View {
  let provider: DashisProvider
  @ObservedObject var store: DashisProviderStore

  var body: some View {
    Form {
      if provider.integration == .collector {
        DashisCollectorProviderControls(store: store, provider: provider)
      } else if provider.integration == .catalogOnly {
        DashisCatalogProviderDetail(provider: provider)
      } else {
        providerControls
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: DashisProviderDetailLayout.contentWidth)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder private var providerControls: some View {
    if provider.id == "codex" {
      CodexNativeControls(store: store)
    } else if provider.id == "claude" {
      ClaudeNativeControls(store: store)
    } else if provider.id == "google" {
      GoogleNativeControls(store: store)
    } else if provider.id == "openrouter" {
      OpenRouterNativeControls(store: store)
    }
  }
}

private struct DashisCollectorProviderControls: View {
  @ObservedObject var store: DashisProviderStore
  let provider: DashisProvider
  @State private var showingConsent = false

  var body: some View {
    Group {
      if routes.isEmpty {
        Section("Connection") {
          DashisProviderNotice(
            title: "No executable method",
            message: "No live collector route is compiled for this provider.",
            symbolName: "xmark.octagon",
            tone: .incident)
        }
      } else if let route {
        Section {
          Picker("Method", selection: routeSelection) {
            ForEach(routes, id: \.id) { candidate in
              Text(methodLabel(candidate)).tag(candidate.id)
            }
          }
          .pickerStyle(.menu)
          .frame(width: DashisProviderDetailLayout.pickerWidth, alignment: .trailing)
          .disabled(store.isLoading(provider.id))
        } header: {
          HStack {
            Text("Connection")
            Spacer()
            if store.hasCollectorSessionState(for: provider.id) {
              Menu {
                Button("Clear Session Data", role: .destructive) {
                  store.clearCollectorSession(for: provider.id)
                }
                .disabled(store.isLoading(provider.id))
              } label: {
                Image(systemName: "ellipsis")
                  .accessibilityLabel("More actions")
              }
              .menuStyle(.borderlessButton)
              .fixedSize()
            }
          }
        }

        if !route.configurationFields.isEmpty {
          Section {
            ForEach(route.configurationFields, id: \.key) { field in
              LabeledContent(field.label) {
                configurationField(field, route: route)
                  .frame(
                    minWidth: 280,
                    idealWidth: DashisProviderDetailLayout.fieldWidth,
                    maxWidth: DashisProviderDetailLayout.fieldWidth)
              }
            }
          } header: {
            Text("Credentials")
          }
        }

        Section {
          DashisFormPrimaryAction(
            title: "Check Usage",
            loadingTitle: "Checking",
            isLoading: store.isLoading(provider.id),
            isDisabled: false
          ) {
            if route.requiresConsent {
              showingConsent = true
            } else {
              Task {
                await store.runCollectorCheck(
                  for: provider.id,
                  consentGranted: false)
              }
            }
          }
        }

        Section {
          DisclosureGroup("Advanced") {
            VStack(alignment: .leading, spacing: 9) {
              LabeledContent("Source", value: sourceName(route.source))
              LabeledContent("Route") {
                Text(route.id)
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
              }
              LabeledContent("Adapter") {
                Text(route.strategyID)
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
              }
            }
            .padding(.top, 8)
          }
        }
      }
    }
    .alert(
      "Run \(provider.name) check?",
      isPresented: $showingConsent
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Run Check") {
        Task {
          await store.runCollectorCheck(
            for: provider.id,
            consentGranted: true)
        }
      }
    } message: {
      Text(route?.riskSummary ?? "This collection method requires confirmation.")
    }
  }

  private var routes: [CollectorLiveRouteDefinition] {
    store.collectorRoutes(for: provider.id)
  }

  private var route: CollectorLiveRouteDefinition? {
    store.selectedCollectorRoute(for: provider.id)
  }

  private var routeSelection: Binding<String> {
    Binding(
      get: {
        route?.id ?? routes.first?.id ?? ""
      },
      set: {
        store.selectCollectorRoute($0, for: provider.id)
      })
  }

  @ViewBuilder
  private func configurationField(
    _ field: CollectorConfigurationField,
    route: CollectorLiveRouteDefinition
  ) -> some View {
    let binding = Binding(
      get: {
        store.collectorInputValue(routeID: route.id, key: field.key)
      },
      set: {
        store.setCollectorInputValue($0, routeID: route.id, key: field.key)
      })
    switch field.kind {
    case .secret:
      SecureField(field.placeholder ?? "", text: binding)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(field.label)
    case .text:
      TextField(field.placeholder ?? "", text: binding)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(field.label)
    }
  }

  private func methodLabel(_ route: CollectorLiveRouteDefinition) -> String {
    let base = sourceName(route.source)
    let sameSourceRoutes = routes.filter { $0.source == route.source }
    guard sameSourceRoutes.count > 1 else { return base }
    return "\(base) · \(strategyName(route.strategyID))"
  }

  private func sourceName(_ source: CollectorSourceMode) -> String {
    switch source {
    case .web:
      "Browser Session"
    case .cli:
      "Command Line"
    case .oauth:
      "Sign In"
    case .api:
      "API"
    case .auto:
      "Automatic"
    }
  }

  private func strategyName(_ strategyID: String) -> String {
    let suffix = strategyID.split(separator: ".").last.map(String.init) ?? strategyID
    return suffix
      .replacingOccurrences(of: "-local", with: "")
      .replacingOccurrences(of: "-https", with: "")
      .replacingOccurrences(of: "-", with: " ")
      .capitalized
      .replacingOccurrences(of: "Cli", with: "CLI")
      .replacingOccurrences(of: "Ide", with: "IDE")
  }

}

private struct DashisCatalogProviderDetail: View {
  let provider: DashisProvider

  var body: some View {
    Section("Availability") {
      LabeledContent(
        "Data sources",
        value: provider.preparedSourceLabels.joined(separator: ", ")
      )

      Text(provider.detailNote)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .contain)
  }
}

private struct DashisProviderMainCard: View {
  let provider: DashisProvider
  let snapshot: ProviderSnapshot?
  let visualization: ProviderVisualization?

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 0) {
        header

        Divider()
          .padding(.vertical, 14)

        if let snapshot, let visualization {
          if visualization.primaryCards.isEmpty {
            emptyState
          } else {
            primaryUsage(visualization.primaryCards)
          }

          if !snapshot.warnings.isEmpty || !snapshot.partialFailures.isEmpty {
            Divider()
              .padding(.vertical, 14)
            notices(snapshot)
          }

          if !visualization.additionalCards.isEmpty {
            Divider()
              .padding(.vertical, 12)
            additionalUsage(visualization.additionalCards)
          }

          Divider()
            .padding(.vertical, 12)
          dataDetails(visualization.metadata)
        } else {
          emptyState
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 2)
    }
    .accessibilityElement(children: .contain)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(provider.name)
          .font(.title3.weight(.semibold))
          .lineLimit(1)

        if let snapshot {
          Text(headerStatus(snapshot))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 16)

      if let scope = snapshot?.scope.label, !scope.isEmpty {
        Text(scope)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .help(scope)
      }
    }
  }

  private var emptyState: some View {
    Text(provider.primary)
      .font(.title.weight(.semibold))
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .minimumScaleFactor(0.8)
      .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
  }

  @ViewBuilder
  private func primaryUsage(_ cards: [ProviderUsageCard]) -> some View {
    if cards.count > 1 {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 22) {
          DashisPrimaryUsageMetric(card: cards[0])
            .frame(minWidth: 240, maxWidth: .infinity)
          Divider()
          DashisPrimaryUsageMetric(card: cards[1])
            .frame(minWidth: 240, maxWidth: .infinity)
        }

        VStack(alignment: .leading, spacing: 16) {
          DashisPrimaryUsageMetric(card: cards[0])
          Divider()
          DashisPrimaryUsageMetric(card: cards[1])
        }
      }
    } else if let card = cards.first {
      DashisPrimaryUsageMetric(card: card)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func notices(_ snapshot: ProviderSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(snapshot.warnings) { warning in
        DashisProviderNotice(
          title: "Warning",
          message: warning.message,
          symbolName: "exclamationmark.triangle",
          tone: .watch
        )
      }
      ForEach(snapshot.partialFailures) { failure in
        DashisProviderNotice(
          title: failure.operation,
          message: failure.message,
          symbolName: "xmark.octagon",
          tone: .incident
        )
      }
    }
  }

  private func additionalUsage(_ cards: [ProviderUsageCard]) -> some View {
    DisclosureGroup("More usage data") {
      VStack(spacing: 0) {
        ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
          DashisSecondaryUsageRow(card: card)
          if index < cards.count - 1 {
            Divider()
          }
        }
      }
      .padding(.top, 8)
    }
  }

  private func dataDetails(_ metadata: [DashisProviderLine]) -> some View {
    DisclosureGroup("Data details") {
      VStack(spacing: 0) {
        ForEach(Array(metadata.enumerated()), id: \.offset) { index, line in
          DashisMetadataRow(line: line)
          if index < metadata.count - 1 {
            Divider()
          }
        }
      }
      .padding(.top, 8)
    }
  }

  private func headerStatus(_ snapshot: ProviderSnapshot) -> String {
    var labels = [FreshnessPolicy.freshness(of: snapshot).label]
    if snapshot.sourceKind != .officialDirect {
      labels.append(snapshot.sourceKind.label)
    }
    return labels.joined(separator: " · ")
  }
}

private struct DashisPrimaryUsageMetric: View {
  let card: ProviderUsageCard

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(card.title)
          .font(.headline)
          .lineLimit(2)
        Spacer(minLength: 8)
        if let statusLabel = card.statusLabel {
          Text(statusLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(DashisTheme.statusColor(card.tone))
        }
      }

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(card.headline)
          .font(.largeTitle.weight(.semibold))
          .monospacedDigit()
        if !card.descriptor.isEmpty {
          Text(card.descriptor)
            .font(.title3)
            .foregroundStyle(.secondary)
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.78)

      if let progress = card.progressFraction {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .tint(DashisUsageProgressStyle.color(for: card, progress: progress))
          .accessibilityLabel(card.title)
      }

      if let supportingText = card.supportingText {
        Text(supportingText)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(card.title)
    .accessibilityValue(accessibilityValue)
  }

  private var accessibilityValue: String {
    [
      [card.headline, card.descriptor].filter { !$0.isEmpty }.joined(separator: " "),
      card.supportingText,
      card.statusLabel
    ]
    .compactMap { $0 }
    .joined(separator: ". ")
  }
}

private struct DashisSecondaryUsageRow: View {
  let card: ProviderUsageCard

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(card.title)
          .lineLimit(2)

        Spacer(minLength: 12)

        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(card.headline)
            .font(.body.weight(.semibold))
            .monospacedDigit()
          if !card.descriptor.isEmpty {
            Text(card.descriptor)
              .foregroundStyle(.secondary)
          }
        }
        .lineLimit(1)

        if let statusLabel = card.statusLabel {
          Text(statusLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(DashisTheme.statusColor(card.tone))
        }
      }

      if let progress = card.progressFraction {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .tint(DashisUsageProgressStyle.color(for: card, progress: progress))
          .accessibilityLabel(card.title)
      }

      if let supportingText = card.supportingText {
        Text(supportingText)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 8)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(card.title)
    .accessibilityValue(accessibilityValue)
  }

  private var accessibilityValue: String {
    [
      [card.headline, card.descriptor].filter { !$0.isEmpty }.joined(separator: " "),
      card.supportingText,
      card.statusLabel
    ]
    .compactMap { $0 }
    .joined(separator: ". ")
  }
}

private enum DashisUsageProgressStyle {
  static func color(for card: ProviderUsageCard, progress: Double) -> Color {
    if card.tone == .incident { return DashisTheme.bad }
    if card.tone == .watch { return DashisTheme.warn }
    switch card.progressKind {
    case .remaining:
      if progress < 0.10 { return DashisTheme.bad }
      if progress < 0.25 { return DashisTheme.warn }
      return DashisTheme.ok
    case .used:
      if progress > 0.90 { return DashisTheme.bad }
      if progress > 0.75 { return DashisTheme.warn }
      return DashisTheme.ok
    case nil:
      return DashisTheme.ok
    }
  }
}

private struct DashisProviderNotice: View {
  let title: String
  let message: String
  let symbolName: String
  let tone: DashisProviderTone

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbolName)
        .foregroundStyle(DashisTheme.statusColor(tone))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.body.weight(.semibold))
        Text(message)
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 2)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(message)
  }
}

private struct DashisMetadataRow: View {
  let line: DashisProviderLine

  var body: some View {
    LabeledContent(line.title) {
      Text(line.value)
        .multilineTextAlignment(.trailing)
    }
    .font(.body)
    .padding(.vertical, 9)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(line.title)
    .accessibilityValue(line.value)
  }
}

private extension DashisProvider {
  var hasNotableStatus: Bool {
    ["partial", "failed", "exceeded"].contains(statusLabel.lowercased())
  }

  var summaryQualifier: String? {
    if hasNotableStatus { return statusLabel }
    guard freshnessLabel != "No data" else { return nil }
    if ["Historical", "Stale", "Expired"].contains(freshnessLabel) {
      return freshnessLabel
    }
    switch sourceLabel {
    case "Experimental": return "Experimental"
    case "Official · Estimated": return "Estimated"
    case "Manual check": return "Manual"
    default:
      return lines.contains(where: { $0.title == "Warning" }) ? "Warning" : nil
    }
  }
}

struct CodexNativeControls: View {
  @ObservedObject var store: DashisProviderStore

  var body: some View {
    Section {
      LabeledContent("Account", value: "Current desktop session")

      DashisFormPrimaryAction(
        title: "Check Desktop Usage",
        loadingTitle: "Checking",
        isLoading: store.isLoading("codex"),
        isDisabled: false
      ) {
        Task { await store.checkCodexDesktop() }
      }
    } header: {
      HStack {
        Text("Personal usage")
        Spacer()
        if shouldShowClear {
          Menu {
            Button("Clear Codex Data", role: .destructive) {
              store.clearCodexSession()
            }
          } label: {
            Image(systemName: "ellipsis")
              .accessibilityLabel("More actions")
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
        }
      }
    }

    Section("Workspace analytics") {
      LabeledContent("Workspace ID") {
        TextField("", text: $store.codexWorkspaceID)
          .textFieldStyle(.roundedBorder)
          .frame(width: DashisProviderDetailLayout.fieldWidth)
          .accessibilityLabel("Workspace ID")
      }
      LabeledContent("Analytics key") {
        SecureField("", text: $store.codexAnalyticsAPIKey)
          .textFieldStyle(.roundedBorder)
          .frame(width: DashisProviderDetailLayout.fieldWidth)
          .accessibilityLabel("Analytics key")
      }
      Stepper(
        "Window: \(store.codexAnalyticsDays) days",
        value: $store.codexAnalyticsDays,
        in: 1...90
      )
      .font(DashisType.body(14))

      HStack {
        Spacer()
        Button("Check Workspace Analytics") {
          Task { await store.checkCodexAnalytics() }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }
    }
    .disabled(store.isLoading("codex"))
  }

  private var shouldShowClear: Bool {
    store.snapshots[ProviderID(rawValue: "codex")] != nil
      || store.isLoading("codex")
      || !store.codexWorkspaceID.isEmpty
      || !store.codexAnalyticsAPIKey.isEmpty
  }
}

struct ClaudeNativeControls: View {
  @ObservedObject var store: DashisProviderStore

  var body: some View {
    Section {
      LabeledContent("Source", value: "Claude Code status line")

      DashisFormPrimaryAction(
        title: "Reload Usage",
        loadingTitle: "Reloading",
        isLoading: store.isLoading("claude"),
        isDisabled: false
      ) {
        Task { await store.reloadClaudeSnapshot() }
      }
    } header: {
      HStack {
        Text("Usage snapshot")
        Spacer()
        if store.snapshots[ProviderID(rawValue: "claude")] != nil {
          Menu {
            Button("Clear Loaded Data", role: .destructive) {
              store.clearClaudeLoadedSnapshot()
            }
          } label: {
            Image(systemName: "ellipsis")
              .accessibilityLabel("More actions")
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
        }
      }
    }

    Section {
      if !["Bridge not configured", "Settings change cancelled."].contains(store.claudeConnectionMessage) {
        LabeledContent("Status") {
          Text(store.claudeConnectionMessage)
            .foregroundStyle(.secondary)
        }
      }

      HStack {
        Spacer()
        Button("Preview Disconnect") {
          store.prepareClaudeDisconnect()
        }
        .buttonStyle(.bordered)

        Button("Preview Connect") {
          store.prepareClaudeConnect()
        }
        .buttonStyle(.bordered)
      }
    } header: {
      Text("Claude Code bridge")
    }

    if let summary = store.claudePatchSummary {
      Section("Pending settings change") {
        Text(summary)
          .fixedSize(horizontal: false, vertical: true)

        HStack {
          Spacer()
          Button("Cancel") {
            store.cancelClaudePendingPatch()
          }
          .buttonStyle(.bordered)

          Button("Apply Change") {
            store.applyClaudePendingPatch()
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        }
      }
    }
  }
}

struct GoogleNativeControls: View {
  @ObservedObject var store: DashisProviderStore

  var body: some View {
    Section {
      Picker("Mode", selection: $store.googleMode) {
        ForEach(DashisGoogleMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: DashisProviderDetailLayout.fieldWidth)
      .accessibilityLabel("Google mode")
      .disabled(store.isLoading("google"))
    } header: {
      HStack {
        Text("Source")
        Spacer()
        if shouldShowClear {
          Menu {
            Button("Clear Google Data", role: .destructive) {
              store.clearGoogleSession()
            }
          } label: {
            Image(systemName: "ellipsis")
              .accessibilityLabel("More actions")
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
        }
      }
    }

    if store.googleMode == .consumer {
      Section {
        LabeledContent("Quota") {
          Button("Open Gemini Official Page") {
            store.openGoogleConsumerQuotaPage()
          }
          .buttonStyle(.borderless)
        }
      } header: {
        Text("Gemini subscription")
      }

      Section {
        LabeledContent("Used") {
          TextField("", text: $store.googleManualUsed)
            .textFieldStyle(.roundedBorder)
            .frame(width: DashisProviderDetailLayout.fieldWidth)
            .accessibilityLabel("Used")
        }
        LabeledContent("Limit") {
          TextField("", text: $store.googleManualLimit)
            .textFieldStyle(.roundedBorder)
            .frame(width: DashisProviderDetailLayout.fieldWidth)
            .accessibilityLabel("Limit")
        }
        LabeledContent("Remaining") {
          TextField("", text: $store.googleManualRemaining)
            .textFieldStyle(.roundedBorder)
            .frame(width: DashisProviderDetailLayout.fieldWidth)
            .accessibilityLabel("Remaining")
        }
        LabeledContent("Unit") {
          TextField("", text: $store.googleManualUnit)
            .textFieldStyle(.roundedBorder)
            .frame(width: DashisProviderDetailLayout.fieldWidth)
            .accessibilityLabel("Unit")
        }

        DashisFormPrimaryAction(
          title: "Record Reading",
          loadingTitle: "Recording",
          isLoading: store.isLoading("google"),
          isDisabled: false
        ) {
          Task { await store.recordGoogleManualReading() }
        }
      } header: {
        Text("Manual reading")
      }
    } else {
      Section {
        LabeledContent("OAuth client ID") {
          TextField("", text: $store.googleOAuthClientID)
            .textFieldStyle(.roundedBorder)
            .frame(width: DashisProviderDetailLayout.fieldWidth)
            .accessibilityLabel("OAuth client ID")
        }
        LabeledContent("Project ID or number") {
          TextField("", text: $store.googleProjectID)
            .textFieldStyle(.roundedBorder)
            .frame(width: DashisProviderDetailLayout.fieldWidth)
            .accessibilityLabel("Project ID or number")
        }
        LabeledContent("Quota IDs (optional)") {
          TextField("", text: $store.googleQuotaIDs)
            .textFieldStyle(.roundedBorder)
            .frame(width: DashisProviderDetailLayout.fieldWidth)
            .accessibilityLabel("Quota IDs, optional")
        }

        if shouldShowGoogleConnectionMessage {
          LabeledContent("Status") {
            Text(store.googleConnectionMessage)
              .foregroundStyle(.secondary)
          }
        }

        DashisFormPrimaryAction(
          title: store.isGoogleProjectConnected ? "Check Quotas" : "Connect Google",
          loadingTitle: store.isGoogleProjectConnected ? "Checking" : "Connecting",
          isLoading: store.isLoading("google"),
          isDisabled: false
        ) {
          if store.isGoogleProjectConnected {
            Task { await store.checkGoogleProject() }
          } else {
            Task { await store.connectGoogleProject() }
          }
        }
      } header: {
        Text("Google Cloud project")
      }
      .disabled(store.isLoading("google"))
    }
  }

  private var shouldShowGoogleConnectionMessage: Bool {
    !["Not connected", "Connected for this app session."].contains(store.googleConnectionMessage)
  }

  private var shouldShowClear: Bool {
    store.snapshots[ProviderID(rawValue: "google")] != nil
      || store.isLoading("google")
      || store.isGoogleProjectConnected
      || !store.googleManualUsed.isEmpty
      || !store.googleManualLimit.isEmpty
      || !store.googleManualRemaining.isEmpty
      || !store.googleOAuthClientID.isEmpty
      || !store.googleProjectID.isEmpty
      || !store.googleQuotaIDs.isEmpty
  }
}

struct OpenRouterNativeControls: View {
  @ObservedObject var store: DashisProviderStore
  @State private var showsClearConfirmation = false

  var body: some View {
    Group {
      Section {
        Picker("Mode", selection: $store.openRouterMode) {
          ForEach(DashisOpenRouterMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: DashisProviderDetailLayout.fieldWidth)
        .accessibilityLabel("OpenRouter mode")
        .disabled(store.isLoading("openrouter"))
      } header: {
        HStack {
          Text("Source")
          Spacer()
          if shouldShowClear {
            Menu {
              Button("Clear Local Session", role: .destructive) {
                showsClearConfirmation = true
              }
            } label: {
              Image(systemName: "ellipsis")
                .accessibilityLabel("More actions")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
          }
        }
      }

      if store.openRouterMode == .singleKey {
        Section {
          if shouldShowOpenRouterConnectionMessage {
            LabeledContent("Status") {
              Text(store.openRouterConnectionMessage)
                .foregroundStyle(.secondary)
            }
          }

          DashisFormPrimaryAction(
            title: store.isOpenRouterOAuthConnected ? "Check Key Limit" : "Connect OpenRouter",
            loadingTitle: store.isOpenRouterOAuthConnected ? "Checking" : "Connecting",
            isLoading: store.isLoading("openrouter"),
            isDisabled: false
          ) {
            if store.isOpenRouterOAuthConnected {
              Task { await store.checkOpenRouterOAuthKey() }
            } else {
              Task { await store.connectOpenRouterOAuth() }
            }
          }
        } header: {
          Text("Single key")
        }
      } else {
        Section {
          LabeledContent("Management key") {
            SecureField("", text: $store.openRouterManagementAPIKey)
              .textFieldStyle(.roundedBorder)
              .frame(width: DashisProviderDetailLayout.fieldWidth)
              .accessibilityLabel("OpenRouter account management key, kept for this app session only")
              .help("OpenRouter requires a management key for account-wide credits, activity, and analytics.")
          }

          LabeledContent("Create key") {
            Link(
              "Open OpenRouter",
              destination: URL(string: "https://openrouter.ai/settings/management-keys")!
            )
          }
        } header: {
          Text("Account access")
        }
        .disabled(store.isLoading("openrouter"))

        Section {
          LabeledContent("Generation ID (optional)") {
            TextField("", text: $store.openRouterGenerationID)
              .textFieldStyle(.roundedBorder)
              .frame(width: DashisProviderDetailLayout.fieldWidth)
              .accessibilityLabel("Generation ID, optional")
          }
          Stepper(
            "Analytics window: \(store.openRouterAnalyticsDays) days",
            value: $store.openRouterAnalyticsDays,
            in: 1...90
          )
          .font(DashisType.body(14))

          DashisFormPrimaryAction(
            title: "Check Whole Account",
            loadingTitle: "Checking",
            isLoading: store.isLoading("openrouter"),
            isDisabled: false
          ) {
            Task { await store.checkOpenRouterAccount() }
          }
        } header: {
          Text("Account analysis")
        }
        .disabled(store.isLoading("openrouter"))

        Section("Recent calls") {
          OpenRouterRecentCallsSection(store: store)
        }
      }
    }
    .confirmationDialog(
      "Clear local OpenRouter session?",
      isPresented: $showsClearConfirmation,
      titleVisibility: .visible
    ) {
      Button("Clear local session", role: .destructive) {
        store.clearOpenRouterSession()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(clearConfirmationMessage)
    }
  }

  private var shouldShowOpenRouterConnectionMessage: Bool {
    !["Not connected", "Connected for this app session."].contains(store.openRouterConnectionMessage)
  }

  private var clearConfirmationMessage: String {
    if store.openRouterMode == .singleKey {
      return "This clears Dashis only. Revoke any server-side key in OpenRouter if needed."
    }
    return "This clears the management key, account snapshot, and recent call metadata from Dashis memory only."
  }

  private var shouldShowClear: Bool {
    store.snapshots[ProviderID(rawValue: "openrouter")] != nil
      || store.isLoading("openrouter")
      || store.isOpenRouterOAuthConnected
      || !store.openRouterManagementAPIKey.isEmpty
      || !store.openRouterGenerationID.isEmpty
      || store.openRouterRecentCallsState != .idle
  }
}

private struct OpenRouterRecentCallsSection: View {
  @ObservedObject var store: DashisProviderStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Stepper(
        "Call window: \(store.openRouterRecentCallsDays) day\(store.openRouterRecentCallsDays == 1 ? "" : "s")",
        value: $store.openRouterRecentCallsDays,
        in: 1...30
      )
      .font(DashisType.body(14))
      .disabled(store.isLoading("openrouter"))

      HStack {
        Spacer()
        Button("Load Call Metadata") {
          Task { await store.loadOpenRouterRecentCalls() }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(store.isLoading("openrouter") || !store.canLoadOpenRouterRecentCalls)
      }

      stateContent
    }
  }

  @ViewBuilder private var stateContent: some View {
    switch store.openRouterRecentCallsState {
    case .idle:
      EmptyView()
    case .loading:
      ProgressView("Loading call metadata")
        .controlSize(.small)
    case .failed(let message):
      DashisProviderNotice(
        title: "Recent calls",
        message: message,
        symbolName: "xmark.octagon",
        tone: .incident
      )
    case .loaded(let page):
      if let truncationMessage = page.truncationMessage {
        DashisProviderNotice(
          title: "Result truncated",
          message: truncationMessage,
          symbolName: "exclamationmark.triangle",
          tone: .watch
        )
      }
      if page.calls.isEmpty {
        Text(page.isTruncated
          ? "No call metadata rows were included in the returned subset."
          : "No call metadata was returned for the selected window.")
          .font(DashisType.body(13))
          .foregroundStyle(.secondary)
      } else {
        Text("\(page.calls.count) unique call row\(page.calls.count == 1 ? "" : "s") · \(page.granularity) buckets")
          .font(DashisType.body(13))
          .foregroundStyle(.secondary)
        VStack(spacing: 0) {
          ForEach(Array(page.calls.enumerated()), id: \.element.id) { index, call in
            OpenRouterRecentCallRow(call: call)
            if index < page.calls.count - 1 {
              Divider()
            }
          }
        }
      }
    }
  }
}

private struct OpenRouterRecentCallRow: View {
  let call: OpenRouterRecentCall

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(call.model ?? call.apiKeyLabel ?? "OpenRouter call")
          .font(DashisType.body(14, .semibold))
          .lineLimit(1)
        Spacer(minLength: 12)
        if let usage = call.usage {
          Text(String(format: "$%.4f", usage))
            .font(DashisType.body(13, .semibold))
            .monospacedDigit()
        }
      }

      Text(call.id)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)

      HStack(spacing: 12) {
        Text(call.bucketStart.formatted(date: .abbreviated, time: .shortened))
        if let apiKeyLabel = call.apiKeyLabel {
          Text("Key: \(apiKeyLabel)")
            .lineLimit(1)
        }
        if let totalTokens = call.totalTokens {
          Text("\(totalTokens.formatted()) tokens")
        }
      }
      .font(DashisType.body(12))
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }
}
