import SwiftUI

struct DashboardView: View {
  @Environment(\.colorScheme) private var colorScheme
  @SceneStorage("dashis.selectedView") private var selectedViewID = DashisDashboardSection.overview.rawValue
  @State private var selectedRunID = DashisSampleData.runs[0].id
  @State private var selectedRange = "7d"
  @State private var selectedModel = "All models"
  @State private var chartMode = DashisChartMode.latency
  @State private var monitorPaused = false

  private var selectedSection: DashisDashboardSection {
    get { DashisDashboardSection(rawValue: selectedViewID) ?? .overview }
    nonmutating set { selectedViewID = newValue.rawValue }
  }

  private var selectedRun: DashisRun {
    DashisSampleData.runs.first { $0.id == selectedRunID } ?? DashisSampleData.runs[0]
  }

  var body: some View {
    NavigationSplitView {
      DashisSidebar(selection: Binding(
        get: { selectedSection },
        set: { selectedSection = $0 }
      ))
      .navigationSplitViewColumnWidth(min: 176, ideal: 218)
    } detail: {
      GeometryReader { proxy in
        HStack(spacing: 0) {
          DashisDashboardDetail(
            selectedSection: selectedSection,
            selectedRunID: $selectedRunID,
            selectedRange: $selectedRange,
            selectedModel: $selectedModel,
            chartMode: $chartMode
          )
          .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

          if proxy.size.width >= 980 {
            Divider().opacity(0.55)
            DashisInspector(run: selectedRun, monitorPaused: $monitorPaused)
              .frame(width: 306)
              .frame(maxHeight: .infinity)
          }
        }
        .background(DashisTheme.page(colorScheme).ignoresSafeArea())
      }
      .navigationTitle("")
    }
  }
}

#Preview {
  DashboardView()
    .frame(width: 1280, height: 860)
}
