import SwiftUI

@main
struct DashisApp: App {
  var body: some Scene {
    WindowGroup {
      DashboardView()
        .frame(minWidth: 1100, minHeight: 720)
    }
    .defaultSize(width: 1280, height: 860)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}
