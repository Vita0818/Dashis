import SwiftUI

@main
struct DashisApp: App {
  var body: some Scene {
    WindowGroup {
      DashboardView()
        .frame(
          minWidth: DashisWindowLayout.minimumWidth,
          minHeight: DashisWindowLayout.minimumHeight
        )
    }
    .defaultSize(
      width: DashisWindowLayout.defaultWidth,
      height: DashisWindowLayout.defaultHeight
    )
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}
