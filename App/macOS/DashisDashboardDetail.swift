import SwiftUI

struct DashisDashboardDetail: View {
  @Binding var selectedID: String
  @ObservedObject var store: DashisProviderStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DashisPageHeader(title: store.title(for: selectedID))
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

  @ViewBuilder private var content: some View {
    if selectedID == DashisSelection.dashboard {
      providerList
    } else if let provider = store.provider(id: selectedID) {
      DashisProviderDetail(provider: provider, store: store)
        .frame(maxWidth: 900, alignment: .leading)
    } else {
      providerList
    }
  }

  private var providerList: some View {
    VStack(spacing: 0) {
      ForEach(store.providers) { provider in
        DashisProviderCard(
          provider: provider,
          isLoading: store.isLoading(provider.id)
        ) {
          if provider.id == ProviderID.openRouter.rawValue,
             store.needsOpenRouterAccountSetup {
            selectedID = provider.id
          } else {
            Task { await store.runPrimaryCheck(for: provider.id) }
          }
        }

        if provider.id != store.providers.last?.id {
          Divider()
        }
      }
    }
    .frame(maxWidth: 900, alignment: .leading)
  }
}
