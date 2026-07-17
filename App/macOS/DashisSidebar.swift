import SwiftUI

struct DashisSidebar: View {
  @Environment(\.colorScheme) private var colorScheme
  let providers: [DashisProvider]
  @Binding var selectionID: String

  var body: some View {
    List {
      Section {
        brand
          .listRowSeparator(.hidden)
          .padding(.vertical, 10)
          .offset(x: 7, y: 9)
      }

      Section {
        navigationRow(
          title: "Dashboard",
          symbolName: "rectangle.3.group",
          id: DashisSelection.dashboard
        )
        .padding(.bottom, 29)
        .offset(x: 5, y: 4)

        ForEach(providers) { provider in
          navigationRow(
            title: provider.name,
            symbolName: provider.symbolName,
            id: provider.id
          )
          .padding(.vertical, 9)
          .offset(x: 5)
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

  private func navigationRow(
    title: String,
    symbolName: String,
    id: String
  ) -> some View {
    Button {
      selectionID = id
    } label: {
      Label(title, systemImage: symbolName)
        .font(DashisType.navigation())
        .foregroundStyle(DashisTheme.primaryText(colorScheme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(selectionID == id ? DashisTheme.accent.opacity(0.14) : .clear)
        .overlay {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(
              selectionID == id ? DashisTheme.accent.opacity(0.32) : .clear,
              lineWidth: 1
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    )
    .accessibilityAddTraits(selectionID == id ? .isSelected : [])
    .accessibilityLabel(title)
    .accessibilityValue(selectionID == id ? "Selected" : "")
  }
}
