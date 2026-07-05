import SwiftUI

struct DashisDashboardDetail: View {
  @Environment(\.colorScheme) private var colorScheme
  let selectedSection: DashisDashboardSection
  @Binding var selectedRunID: String
  @Binding var selectedRange: String
  @Binding var selectedModel: String
  @Binding var chartMode: DashisChartMode

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header
        content
      }
      .padding(.horizontal, 30)
      .padding(.top, 26)
      .padding(.bottom, 30)
      .frame(maxWidth: 1180)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .scrollContentBackground(.hidden)
  }

  private var header: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 18) {
        DashisPageHeader(title: selectedSection.title)
        if showsControls {
          Spacer(minLength: 12)
          controls
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        DashisPageHeader(title: selectedSection.title)
        if showsControls {
          controls
        }
      }
    }
  }

  private var showsControls: Bool {
    selectedSection != .accounts
  }

  @ViewBuilder private var content: some View {
    switch selectedSection {
    case .accounts:
      accountsPanel
    case .runs, .alerts:
      runsTable
    default:
      DashisMetricGrid(metrics: DashisSampleData.metrics)
      DashisChartPanel(chartMode: $chartMode)
      runsTable
    }
  }

  private var controls: some View {
    HStack(spacing: 8) {
      Picker("Range", selection: $selectedRange) {
        Text("24h").tag("24h")
        Text("7d").tag("7d")
        Text("30d").tag("30d")
      }
      .frame(width: 118)

      Picker("Model", selection: $selectedModel) {
        Text("All models").tag("All models")
        Text("gpt-4.1").tag("gpt-4.1")
        Text("gpt-4.1-mini").tag("gpt-4.1-mini")
        Text("o4-mini").tag("o4-mini")
      }
      .frame(width: 156)
    }
  }

  private var accountsPanel: some View {
    VStack(spacing: 0) {
      ForEach(DashisSampleData.accounts) { account in
        accountRow(account)
        if account.id != DashisSampleData.accounts.last?.id {
          Divider()
        }
      }
    }
    .dashisGlassCard(cornerRadius: 14)
  }

  private func accountRow(_ account: DashisAccountStatus) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      Text(account.title)
        .font(DashisType.body(14, .semibold))
      Spacer(minLength: 12)
      Text(account.primary)
      Text(account.secondary)
        .foregroundStyle(DashisTheme.secondaryText(colorScheme))
      ProgressView(value: account.usedPercent, total: 100)
        .frame(width: 118)
    }
    .font(DashisType.caption(12, .medium))
    .foregroundStyle(DashisTheme.primaryText(colorScheme))
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
  }

  private var runsTable: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Runs")
        .font(DashisType.body(16, .semibold))
        .padding(16)

      Divider()

      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
        GridRow {
          tableHeader("Run")
          tableHeader("Model")
          tableHeader("Status")
          tableHeader("Latency")
          tableHeader("Cost")
          tableHeader("Quality")
          tableHeader("Owner")
        }
        Divider().gridCellColumns(7)
        ForEach(DashisSampleData.runs) { run in
          GridRow {
            runTitle(run)
            mono(run.model)
            statusBadge(run.status)
            Text("\(run.latency)ms")
            Text(String(format: "$%.1f", run.cost))
            Text(String(format: "%.1f%%", run.quality))
            Text(run.owner)
          }
          .font(DashisType.caption(12, .medium))
          .foregroundStyle(DashisTheme.primaryText(colorScheme))
          .padding(.vertical, 10)
          .contentShape(Rectangle())
          .onTapGesture { selectedRunID = run.id }
          Divider().gridCellColumns(7)
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 4)
    }
    .dashisGlassCard(cornerRadius: 16)
  }

  private func tableHeader(_ value: String) -> some View {
    Text(value.uppercased())
      .font(DashisType.caption(10, .bold))
      .foregroundStyle(DashisTheme.secondaryText(colorScheme))
      .padding(.vertical, 9)
  }

  private func runTitle(_ run: DashisRun) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(run.title)
        .font(DashisType.caption(12, .semibold))
      Text("\(run.id) · \(run.flow)")
        .font(DashisType.mono(11))
        .foregroundStyle(DashisTheme.secondaryText(colorScheme))
    }
  }

  private func mono(_ value: String) -> some View {
    Text(value)
      .font(DashisType.mono(12))
      .foregroundStyle(DashisTheme.secondaryText(colorScheme))
  }

  private func statusBadge(_ status: DashisRunStatus) -> some View {
    Text(status.rawValue)
      .font(DashisType.caption(11, .bold))
      .foregroundStyle(DashisTheme.statusColor(status))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(DashisTheme.statusColor(status).opacity(0.13), in: Capsule())
  }
}
