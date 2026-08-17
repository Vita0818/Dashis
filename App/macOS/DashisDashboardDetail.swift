import AppKit
import SwiftUI

struct DashisDashboardDetail: View {
  @Binding var selectedID: String
  @ObservedObject var store: DashisProviderStore

  @ViewBuilder
  var body: some View {
    if selectedID == DashisSelection.settings {
      DashisSettingsWorkspace(store: store)
    } else if selectedID == DashisSelection.dashboard
        || selectedID == DashisSelection.providers {
      dashboardOverview
        .navigationTitle("Dashboard")
    } else if let provider = store.provider(id: selectedID) {
      DashisProviderDetail(provider: provider, store: store)
        .navigationTitle(provider.name)
    } else {
      dashboardOverview
        .navigationTitle("Dashboard")
    }
  }

  @ViewBuilder
  private var dashboardOverview: some View {
    if store.visibleProviders.isEmpty {
      ContentUnavailableView(
        "No Providers Shown",
        systemImage: "eye.slash",
        description: Text("Turn on a provider in Settings.")
      )
    } else {
      dashboardProviderList
    }
  }

  private var dashboardProviderList: some View {
    ScrollView {
      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: 350, maximum: 520),
            spacing: 16,
            alignment: .top)
        ],
        alignment: .center,
        spacing: 16
      ) {
        ForEach(store.visibleProviders) { provider in
          DashisProviderCard(
            provider: provider,
            snapshot: store.snapshots[ProviderID(rawValue: provider.id)]
          ) {
            selectedID = provider.id
          }
        }
      }
      .frame(maxWidth: 1_056)
      .padding(.horizontal, 28)
      .padding(.vertical, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

private struct DashisSettingsWorkspace: View {
  @ObservedObject var store: DashisProviderStore
  @SceneStorage("dashis.settings.selectedProvider") private var selectedProviderID = ProviderID.codex.rawValue
  @State private var providerSearch = ""

  var body: some View {
    HStack(spacing: 0) {
      settingsSidebar

      Divider()

      settingsDetail
        .frame(
          minWidth: 0,
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: .top
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle(selectedProvider?.name ?? "Settings")
    .onAppear {
      normalizeSelection()
    }
  }

  private var settingsSidebar: some View {
    VStack(spacing: 0) {
      DashisProviderSearchField(
        text: $providerSearch,
        prompt: "Provider settings"
      )
      .frame(height: 28)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)

      Divider()

      List(selection: selection) {
        Section("Providers") {
          if filteredProviders.isEmpty {
            Text("No matching providers")
              .foregroundStyle(.secondary)
          } else {
            ForEach(filteredProviders) { provider in
              HStack {
                Text(provider.name)
                  .lineLimit(1)
                  .truncationMode(.tail)
                  .frame(
                    minWidth: 0,
                    maxWidth: .infinity,
                    alignment: .leading
                  )
                  .help(provider.name)

                Toggle(
                  "Show \(provider.name) in Dashboard and Sidebar",
                  isOn: visibilityBinding(for: provider)
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .help(
                  store.isProviderVisible(provider.id)
                    ? "Shown in Dashboard and Sidebar"
                    : "Hidden from Dashboard and Sidebar"
                )
              }
              .tag(provider.id)
            }
          }
        }
      }
      .listStyle(.inset)
      .id("dashis.settings-sidebar.vertical-layout.v1")
    }
    .frame(width: DashisWindowLayout.settingsSidebarWidth)
    .background(.regularMaterial)
  }

  @ViewBuilder
  private var settingsDetail: some View {
    if let provider = selectedProvider {
      DashisProviderSettingsDetail(provider: provider, store: store)
    } else {
      ContentUnavailableView(
        "No Provider Selected",
        systemImage: "slider.horizontal.3",
        description: Text("Choose a provider from the settings menu.")
      )
    }
  }

  private var selectedProvider: DashisProvider? {
    store.provider(id: selectedProviderID)
  }

  private var selection: Binding<String?> {
    Binding(
      get: { selectedProviderID },
      set: { newValue in
        if let newValue {
          selectedProviderID = newValue
        }
      }
    )
  }

  private var filteredProviders: [DashisProvider] {
    let query = providerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return store.providers }
    return store.providers.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || $0.kind.localizedCaseInsensitiveContains(query)
    }
  }

  private func visibilityBinding(for provider: DashisProvider) -> Binding<Bool> {
    Binding(
      get: { store.isProviderVisible(provider.id) },
      set: { store.setProviderVisible($0, for: provider.id) }
    )
  }

  private func normalizeSelection() {
    guard selectedProvider == nil else { return }
    selectedProviderID = store.providers.first?.id ?? ProviderID.codex.rawValue
  }
}

private struct DashisProviderSearchField: NSViewRepresentable {
  @Binding var text: String
  let prompt: String

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSSearchField {
    let searchField = NSSearchField()
    searchField.placeholderString = prompt
    searchField.sendsSearchStringImmediately = true
    searchField.delegate = context.coordinator
    return searchField
  }

  func updateNSView(_ nsView: NSSearchField, context: Context) {
    context.coordinator.text = $text
    if nsView.stringValue != text {
      nsView.stringValue = text
    }
    if nsView.placeholderString != prompt {
      nsView.placeholderString = prompt
    }
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let searchField = notification.object as? NSSearchField else { return }
      text.wrappedValue = searchField.stringValue
    }
  }
}
