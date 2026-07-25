import SwiftUI

struct DashboardView: View {
  @Environment(\.colorScheme) private var colorScheme
  @SceneStorage("dashis.selectedView") private var selectedViewID = DashisSelection.dashboard
  @StateObject private var store = DashisProviderStore()

  var body: some View {
    NavigationSplitView {
      DashisSidebar(
        providers: store.providers,
        selectionID: $selectedViewID
      )
      .navigationSplitViewColumnWidth(min: 176, ideal: 218)
    } detail: {
      DashisDashboardDetail(
        selectedID: $selectedViewID,
        store: store
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(DashisTheme.page(colorScheme).ignoresSafeArea())
      .navigationTitle("")
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
      }
    }
  }
}

#Preview {
  DashboardView()
    .frame(width: 1280, height: 860)
}
