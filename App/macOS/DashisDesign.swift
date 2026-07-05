import SwiftUI

enum DashisTheme {
  static let accent = Color(nsColor: .systemBlue)
  static let ok = Color(nsColor: .systemGreen)
  static let warn = Color(nsColor: .systemOrange)
  static let bad = Color(nsColor: .systemRed)

  static func page(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? .black : .white
  }

  static func primaryText(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(red: 0.96, green: 0.96, blue: 0.97) : Color(red: 0.04, green: 0.04, blue: 0.04)
  }

  static func secondaryText(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(red: 0.65, green: 0.65, blue: 0.68) : Color(red: 0.38, green: 0.38, blue: 0.40)
  }

  static func tertiaryText(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(red: 0.44, green: 0.44, blue: 0.47) : Color(red: 0.56, green: 0.56, blue: 0.59)
  }

  static func surface(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(red: 0.06, green: 0.06, blue: 0.065) : .white
  }

  static func mutedSurface(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(red: 0.095, green: 0.095, blue: 0.10) : Color(red: 0.965, green: 0.965, blue: 0.975)
  }

  static func stroke(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.11)
  }

  static func strongStroke(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.18)
  }

  static func statusColor(_ status: DashisRunStatus) -> Color {
    switch status {
    case .healthy: ok
    case .watch: warn
    case .incident: bad
    }
  }
}

enum DashisType {
  static func brand(_ size: CGFloat = 30, _ weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .serif)
  }

  static func title(_ size: CGFloat = 30, _ weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .serif)
  }

  static func body(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight)
  }

  static func caption(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
    .system(size: size, weight: weight)
  }

  static func mono(_ size: CGFloat = 12, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}

extension View {
  func dashisGlassCard(
    cornerRadius: CGFloat = 16,
    fillOpacity: Double = 0.72,
    shadowOpacity: Double = 0.08
  ) -> some View {
    modifier(DashisGlassCardModifier(
      cornerRadius: cornerRadius,
      fillOpacity: fillOpacity,
      shadowOpacity: shadowOpacity
    ))
  }
}

private struct DashisGlassCardModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let cornerRadius: CGFloat
  let fillOpacity: Double
  let shadowOpacity: Double

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    content
      .background {
        shape.fill(DashisTheme.surface(colorScheme).opacity(colorScheme == .dark ? min(fillOpacity, 0.42) : fillOpacity))
      }
      .background(.ultraThinMaterial, in: shape)
      .overlay {
        shape.stroke(
          LinearGradient(
            colors: [
              Color.white.opacity(colorScheme == .dark ? 0.08 : 0.72),
              DashisTheme.stroke(colorScheme),
              DashisTheme.accent.opacity(colorScheme == .dark ? 0.10 : 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1
        )
      }
      .shadow(
        color: Color.black.opacity(colorScheme == .dark ? max(shadowOpacity * 0.35, 0.04) : shadowOpacity),
        radius: 18,
        x: 0,
        y: 10
      )
  }
}

struct DashisPageHeader: View {
  @Environment(\.colorScheme) private var colorScheme
  let title: String

  var body: some View {
    Text(title)
      .font(DashisType.title(32))
      .foregroundStyle(DashisTheme.primaryText(colorScheme))
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
