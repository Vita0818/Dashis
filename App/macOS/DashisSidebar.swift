import SwiftUI

struct DashisSidebar: View {
  @Environment(\.colorScheme) private var colorScheme
  let providers: [DashisProvider]
  @Binding var selectionID: String

  var body: some View {
    List(selection: selection) {
      Section {
        brand
          .listRowSeparator(.hidden)
          .padding(.vertical, 10)
          .offset(x: 7, y: 9)
      }

      Section {
        navigationLabel("Dashboard")
          .tag(DashisSelection.dashboard)

        navigationLabel("Settings")
          .tag(DashisSelection.settings)
      }

      if !providers.isEmpty {
        Section("Providers") {
          ForEach(providers) { provider in
            navigationLabel(provider.name)
              .help(provider.name)
              .tag(provider.id)
          }
        }
      }
    }
    .listStyle(.sidebar)
    .id("dashis.primary-sidebar.vertical-layout.v1")
  }

  private var brand: some View {
    Text("Dashis")
      .font(DashisType.brand(28))
      .foregroundStyle(DashisTheme.primaryText(colorScheme))
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  private func navigationLabel(_ title: String) -> some View {
    Text(title)
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(
        minWidth: 0,
        maxWidth: .infinity,
        alignment: .leading
      )
  }

  private var selection: Binding<String?> {
    Binding(
      get: { selectionID },
      set: { newValue in
        if let newValue {
          selectionID = newValue
        }
      }
    )
  }
}
