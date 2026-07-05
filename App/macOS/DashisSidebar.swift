import SwiftUI

struct DashisSidebar: View {
  @Environment(\.colorScheme) private var colorScheme
  @Binding var selection: DashisDashboardSection

  var body: some View {
    List(selection: Binding<DashisDashboardSection?>(
      get: { selection },
      set: { value in
        if let value {
          selection = value
        }
      }
    )) {
      Section {
        brand
          .listRowSeparator(.hidden)
          .padding(.vertical, 10)
      }

      Section {
        ForEach(DashisDashboardSection.allCases) { item in
          Label(item.title, systemImage: item.symbolName)
            .tag(item)
        }
      }
    }
    .listStyle(.sidebar)
  }

  private var brand: some View {
    Text("Dashis")
      .font(DashisType.brand(28))
      .foregroundStyle(DashisTheme.primaryText(colorScheme))
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
