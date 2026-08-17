import SwiftUI

struct DashboardView: View {
  @SceneStorage("dashis.selectedView") private var selectedViewID = DashisSelection.dashboard
  @StateObject private var store = DashisProviderStore()

  var body: some View {
    NavigationSplitView {
      DashisSidebar(
        providers: store.visibleProviders,
        selectionID: $selectedViewID
      )
      .navigationSplitViewColumnWidth(
        min: DashisWindowLayout.primarySidebarWidth,
        ideal: DashisWindowLayout.primarySidebarWidth,
        max: DashisWindowLayout.primarySidebarWidth
      )
    } detail: {
      DashisDashboardDetail(
        selectedID: $selectedViewID,
        store: store
      )
    }
    .onAppear {
#if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--visual-qa") {
        selectedViewID = ProviderID.codex.rawValue
        return
      }
#endif
      if selectedViewID == DashisSelection.settings {
        selectedViewID = DashisSelection.dashboard
        return
      }
      selectedViewID = store.normalizedDisplaySelection(selectedViewID)
    }
  }
}

#Preview {
  DashboardView()
    .frame(
      width: DashisWindowLayout.defaultWidth,
      height: DashisWindowLayout.defaultHeight
    )
}
