import SwiftUI

enum DashisWindowLayout {
  static let minimumWidth: CGFloat = 960
  static let minimumHeight: CGFloat = 640
  static let defaultWidth: CGFloat = 1_160
  static let defaultHeight: CGFloat = 760

  // The primary width belongs to the only NavigationSplitView in the window.
  // The Settings width is a fixed panel inside its detail area, so it cannot
  // create independent column visibility or resize the primary Sidebar.
  static let primarySidebarWidth: CGFloat = 218
  static let settingsSidebarWidth: CGFloat = 220
}

enum DashisTheme {
  static let ok = Color(nsColor: .systemGreen)
  static let warn = Color(nsColor: .systemOrange)
  static let bad = Color(nsColor: .systemRed)

  static func primaryText(_ scheme: ColorScheme) -> Color {
    scheme == .dark
      ? Color(red: 0.96, green: 0.96, blue: 0.97)
      : Color(red: 0.04, green: 0.04, blue: 0.04)
  }

  static func statusColor(_ status: DashisProviderTone) -> Color {
    switch status {
    case .connected: ok
    case .watch: warn
    case .incident: bad
    }
  }
}

enum DashisType {
  static func brand(_ size: CGFloat = 30, _ weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .serif)
  }

  static func body(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight)
  }
}
