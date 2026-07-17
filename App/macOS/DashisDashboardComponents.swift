import SwiftUI

struct DashisProviderCard: View {
  let provider: DashisProvider
  let isLoading: Bool
  let onPrimaryAction: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 20) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 20) {
          providerIdentity
            .frame(width: 180, alignment: .leading)
          primaryValue
        }

        VStack(alignment: .leading, spacing: 5) {
          providerIdentity
          primaryValue
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(provider.name)
      .accessibilityValue(provider.primary)
      .accessibilityAddTraits(.isHeader)
      .accessibilityCustomContent("Provider type", provider.kind)
      .accessibilityCustomContent("Source", provider.sourceLabel)
      .accessibilityCustomContent("Freshness", provider.freshnessLabel)
      .accessibilityCustomContent("Status", provider.statusLabel)

      VStack(alignment: .trailing, spacing: 8) {
        if let qualifier = provider.summaryQualifier {
          DashisProviderQualifier(provider: provider, label: qualifier)
        }

        if let actionTitle = provider.actionTitle {
          Button {
            onPrimaryAction()
          } label: {
            HStack(spacing: 7) {
              if isLoading {
                ProgressView()
                  .controlSize(.small)
                  .accessibilityHidden(true)
              }
              Text(isLoading ? "Checking" : actionTitle)
            }
          }
          .buttonStyle(.bordered)
          .disabled(isLoading)
          .accessibilityLabel(isLoading ? "Checking \(provider.name)" : "\(actionTitle) for \(provider.name)")
          .accessibilityValue(isLoading ? "In progress" : "")
        }
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 18)
    .accessibilityElement(children: .contain)
  }

  private var providerIdentity: some View {
    HStack(spacing: 12) {
      Image(systemName: provider.symbolName)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 24)
        .accessibilityHidden(true)
      Text(provider.name)
        .font(DashisType.body(18, .semibold))
    }
  }

  private var primaryValue: some View {
    Text(provider.primary)
      .font(DashisType.title(24))
      .lineLimit(1)
      .monospacedDigit()
  }
}

private struct DashisProviderQualifier: View {
  let provider: DashisProvider
  let label: String

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(DashisTheme.statusColor(provider.tone))
        .frame(width: 7, height: 7)
        .accessibilityHidden(true)
      Text(label)
        .font(DashisType.body(13, .semibold))
    }
    .foregroundStyle(DashisTheme.statusColor(provider.tone))
    .accessibilityHidden(true)
  }
}

struct DashisProviderDetail: View {
  let provider: DashisProvider
  @ObservedObject var store: DashisProviderStore

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      if let snapshot, let visualization {
        if !visualization.primaryCards.isEmpty {
          usageSection(snapshot: snapshot, cards: visualization.primaryCards)
        }

        if !snapshot.warnings.isEmpty || !snapshot.partialFailures.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
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

        if !visualization.additionalCards.isEmpty {
          DisclosureGroup("More usage data") {
            usageGrid(cards: visualization.additionalCards)
              .padding(.top, 14)
          }
          .font(DashisType.body(14, .medium))
        }

        DisclosureGroup("Data details") {
          VStack(spacing: 0) {
            ForEach(Array(visualization.metadata.enumerated()), id: \.offset) { index, line in
              DashisMetadataRow(line: line)
              if index < visualization.metadata.count - 1 {
                Divider()
              }
            }
          }
          .padding(.top, 10)
        }
        .font(DashisType.body(14, .medium))
      }

      if snapshot != nil {
        Divider()
      }

      providerControls
    }
  }

  private var snapshot: ProviderSnapshot? {
    store.snapshots[ProviderID(rawValue: provider.id)]
  }

  private var visualization: ProviderVisualization? {
    snapshot.map { ProviderVisualizationProjection.make(snapshot: $0) }
  }

  @ViewBuilder private func usageSection(
    snapshot: ProviderSnapshot,
    cards: [ProviderUsageCard]
  ) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(snapshot.windows.isEmpty && snapshot.balance == nil ? "Usage" : "Balance")
        .font(DashisType.title(22))
        .accessibilityAddTraits(.isHeader)
      usageGrid(cards: cards)
    }
  }

  private func usageGrid(cards: [ProviderUsageCard]) -> some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(minimum: 280), spacing: 16),
        GridItem(.flexible(minimum: 280), spacing: 16)
      ],
      alignment: .leading,
      spacing: 16
    ) {
      ForEach(cards) { card in
        DashisUsageCard(card: card)
      }
    }
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

private struct DashisUsageCard: View {
  @Environment(\.colorScheme) private var colorScheme
  let card: ProviderUsageCard

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(card.title)
          .font(DashisType.body(14, .regular))
          .foregroundStyle(DashisTheme.secondaryText(colorScheme))
          .lineLimit(2)
        Spacer(minLength: 8)
        if let statusLabel = card.statusLabel {
          Text(statusLabel)
            .font(DashisType.caption(11, .semibold))
            .foregroundStyle(DashisTheme.statusColor(card.tone))
        }
      }

      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(card.headline)
          .font(DashisType.title(32))
          .monospacedDigit()
        if !card.descriptor.isEmpty {
          Text(card.descriptor)
            .font(DashisType.body(17))
            .foregroundStyle(DashisTheme.secondaryText(colorScheme))
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.78)

      if let progress = card.progressFraction {
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(DashisTheme.mutedSurface(colorScheme))
            if progress > 0 {
              Capsule()
                .fill(progressColor(progress))
                .frame(width: geometry.size.width * progress)
            }
          }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
      }

      if let supportingText = card.supportingText {
        Text(supportingText)
          .font(DashisType.caption(13, .regular))
          .foregroundStyle(DashisTheme.tertiaryText(colorScheme))
          .lineLimit(2)
      }

      Spacer(minLength: 0)
    }
    .padding(22)
    .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
    .dashisCardSurface(cornerRadius: 17)
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

  private func progressColor(_ progress: Double) -> Color {
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
  @Environment(\.colorScheme) private var colorScheme
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
          .font(DashisType.body(14, .semibold))
        Text(message)
          .font(DashisType.body(14))
          .foregroundStyle(DashisTheme.secondaryText(colorScheme))
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
  @Environment(\.colorScheme) private var colorScheme
  let line: DashisProviderLine

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 20) {
      Text(line.title)
        .foregroundStyle(DashisTheme.secondaryText(colorScheme))
      Spacer(minLength: 12)
      Text(line.value)
        .foregroundStyle(DashisTheme.primaryText(colorScheme))
        .multilineTextAlignment(.trailing)
    }
    .font(DashisType.body(14))
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
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Button {
          Task { await store.checkCodexDesktop() }
        } label: {
          Label("Check desktop usage", systemImage: "person.crop.circle.badge.checkmark")
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isLoading("codex"))

        if shouldShowClear {
          Button {
            store.clearCodexSession()
          } label: {
            Label("Clear Codex data", systemImage: "xmark.circle")
          }
          .buttonStyle(.bordered)
        }
      }

      Divider()

      DisclosureGroup("Workspace analytics") {
        VStack(alignment: .leading, spacing: 12) {
          LabeledContent("Workspace ID") {
            TextField("", text: $store.codexWorkspaceID)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 420)
              .accessibilityLabel("Workspace ID")
          }
          LabeledContent("Analytics key") {
            SecureField("", text: $store.codexAnalyticsAPIKey)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 420)
              .accessibilityLabel("Analytics key")
          }
          Stepper(
            "Window: \(store.codexAnalyticsDays) days",
            value: $store.codexAnalyticsDays,
            in: 1...90
          )
          .font(DashisType.body(14))
          Button {
            Task { await store.checkCodexAnalytics() }
          } label: {
            Label("Check workspace analytics", systemImage: "chart.bar.xaxis")
          }
          .buttonStyle(.bordered)
        }
        .padding(.top, 10)
      }
      .disabled(store.isLoading("codex"))
    }
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
    VStack(alignment: .leading, spacing: 12) {
      if store.claudePatchSummary == nil
        && !["Bridge not configured", "Settings change cancelled."].contains(store.claudeConnectionMessage) {
        Text(store.claudeConnectionMessage)
          .font(DashisType.body(14))
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 10) {
        Button {
          store.prepareClaudeConnect()
        } label: {
          Label("Preview connect", systemImage: "link.badge.plus")
        }
        .buttonStyle(.borderedProminent)

        Button {
          store.prepareClaudeDisconnect()
        } label: {
          Label("Preview disconnect", systemImage: "link.badge.minus")
        }
        .buttonStyle(.bordered)
      }

      if let summary = store.claudePatchSummary {
        VStack(alignment: .leading, spacing: 10) {
          Text(summary)
            .font(DashisType.body(14))
          HStack(spacing: 10) {
            Button("Apply change") {
              store.applyClaudePendingPatch()
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") {
              store.cancelClaudePendingPatch()
            }
            .buttonStyle(.bordered)
          }
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
      }

      Divider()

      HStack(spacing: 10) {
        Button {
          Task { await store.reloadClaudeSnapshot() }
        } label: {
          Label("Reload snapshot", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isLoading("claude"))

        if store.snapshots[ProviderID(rawValue: "claude")] != nil {
          Button {
            store.clearClaudeLoadedSnapshot()
          } label: {
            Label("Clear loaded data", systemImage: "xmark.circle")
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }
}

struct GoogleNativeControls: View {
  @ObservedObject var store: DashisProviderStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Mode", selection: $store.googleMode) {
        ForEach(DashisGoogleMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityLabel("Google mode")
      .disabled(store.isLoading("google"))

      if store.googleMode == .consumer {
        Button {
          store.openGoogleConsumerQuotaPage()
        } label: {
          Label("Open Gemini official page", systemImage: "arrow.up.right.square")
        }
        .buttonStyle(.borderedProminent)
        .help("Antigravity users can check quota with /credits.")

        DisclosureGroup("Manual reading") {
          VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Used") {
              TextField("", text: $store.googleManualUsed)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Used")
            }
            LabeledContent("Limit") {
              TextField("", text: $store.googleManualLimit)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Limit")
            }
            LabeledContent("Remaining") {
              TextField("", text: $store.googleManualRemaining)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Remaining")
            }
            LabeledContent("Unit") {
              TextField("", text: $store.googleManualUnit)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Unit")
            }
            Button {
              Task { await store.recordGoogleManualReading() }
            } label: {
              Label("Record reading", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
          }
          .padding(.top, 10)
        }

        if shouldShowClear {
          Button {
            store.clearGoogleSession()
          } label: {
            Label("Clear Google data", systemImage: "xmark.circle")
          }
          .buttonStyle(.bordered)
        }
      } else {
        LabeledContent("OAuth client ID") {
          TextField("", text: $store.googleOAuthClientID)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("OAuth client ID")
        }
        .disabled(store.isLoading("google"))
        LabeledContent("Project ID or number") {
          TextField("", text: $store.googleProjectID)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Project ID or number")
        }
        .disabled(store.isLoading("google"))
        LabeledContent("Quota IDs (optional)") {
          TextField("", text: $store.googleQuotaIDs)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Quota IDs, optional")
        }
        .disabled(store.isLoading("google"))
        if shouldShowGoogleConnectionMessage {
          Text(store.googleConnectionMessage)
            .font(DashisType.body(14))
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 10) {
          Button {
            Task { await store.connectGoogleProject() }
          } label: {
            Label("Connect Google", systemImage: "person.crop.circle.badge.checkmark")
          }
          .buttonStyle(.borderedProminent)
          .disabled(store.isLoading("google"))

          Button {
            Task { await store.checkGoogleProject() }
          } label: {
            Label("Check quotas", systemImage: "chart.bar")
          }
          .buttonStyle(.bordered)
          .disabled(store.isLoading("google") || !store.isGoogleProjectConnected)

          if shouldShowClear {
            Button {
              store.clearGoogleSession()
            } label: {
              Label("Clear Google session", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
          }
        }
      }
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
    VStack(alignment: .leading, spacing: 12) {
      Picker("Mode", selection: $store.openRouterMode) {
        ForEach(DashisOpenRouterMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityLabel("OpenRouter mode")
      .disabled(store.isLoading("openrouter"))

      if store.openRouterMode == .oauthKey {
        if shouldShowOpenRouterConnectionMessage {
          Text(store.openRouterConnectionMessage)
            .font(DashisType.body(14))
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 10) {
          if store.isOpenRouterOAuthConnected {
            Button {
              Task { await store.checkOpenRouterOAuthKey() }
            } label: {
              Label("Check key limit", systemImage: "gauge")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isLoading("openrouter"))
          } else {
            Button {
              Task { await store.connectOpenRouterOAuth() }
            } label: {
              Label("Connect OpenRouter", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isLoading("openrouter"))
          }

          if shouldShowClear {
            Button(role: .destructive) {
              showsClearConfirmation = true
            } label: {
              Label("Clear local session", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
          }
        }
      } else {
        LabeledContent("Management key") {
          SecureField("", text: $store.openRouterManagementAPIKey)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Management key")
        }
        .disabled(store.isLoading("openrouter"))
        LabeledContent("Generation ID (optional)") {
          TextField("", text: $store.openRouterGenerationID)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Generation ID, optional")
        }
        .disabled(store.isLoading("openrouter"))
        Stepper(
          "Window: \(store.openRouterAnalyticsDays) days",
          value: $store.openRouterAnalyticsDays,
          in: 1...90
        )
        .font(DashisType.body(14))
        .disabled(store.isLoading("openrouter"))

        HStack(spacing: 10) {
          Button {
            Task { await store.checkOpenRouterManagement() }
          } label: {
            Label("Check management data", systemImage: "network")
          }
          .buttonStyle(.borderedProminent)
          .disabled(store.isLoading("openrouter"))

          if shouldShowClear {
            Button(role: .destructive) {
              showsClearConfirmation = true
            } label: {
              Label("Clear local session", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
          }
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
      Text("This clears Dashis only. Revoke any server-side key in OpenRouter if needed.")
    }
  }

  private var shouldShowOpenRouterConnectionMessage: Bool {
    !["Not connected", "Connected for this app session."].contains(store.openRouterConnectionMessage)
  }

  private var shouldShowClear: Bool {
    store.snapshots[ProviderID(rawValue: "openrouter")] != nil
      || store.isLoading("openrouter")
      || store.isOpenRouterOAuthConnected
      || !store.openRouterManagementAPIKey.isEmpty
      || !store.openRouterGenerationID.isEmpty
  }
}
