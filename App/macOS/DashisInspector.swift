import SwiftUI

struct DashisInspector: View {
  @Environment(\.colorScheme) private var colorScheme
  let run: DashisRun
  @Binding var monitorPaused: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header
        detailCard
        signalCard
        pauseButton
      }
      .padding(16)
    }
    .scrollContentBackground(.hidden)
    .background(DashisTheme.mutedSurface(colorScheme).opacity(colorScheme == .dark ? 0.28 : 0.72))
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(run.title)
        .font(DashisType.title(25))
        .foregroundStyle(DashisTheme.primaryText(colorScheme))
      Spacer(minLength: 8)
      Text(run.status.rawValue)
        .font(DashisType.caption(11, .bold))
        .foregroundStyle(DashisTheme.statusColor(run.status))
    }
  }

  private var detailCard: some View {
    VStack(spacing: 0) {
      detailRow("Status", run.status.rawValue)
      detailRow("Guardrail", run.guardrail)
      detailRow("Tokens", run.tokens)
      detailRow("Error budget", run.budget)
    }
    .dashisGlassCard(cornerRadius: 14, fillOpacity: 0.62, shadowOpacity: 0.04)
  }

  private var signalCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Signals")
        .font(DashisType.body(16, .semibold))

      ForEach(run.signals, id: \.title) { signal in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(signal.title)
            Spacer()
            Text("\(signal.value)%")
          }
          .font(DashisType.caption(12, .semibold))

          GeometryReader { proxy in
            Capsule()
              .fill(DashisTheme.mutedSurface(colorScheme))
              .overlay(alignment: .leading) {
                Capsule()
                  .fill(DashisTheme.statusColor(signal.tone))
                  .frame(width: proxy.size.width * CGFloat(signal.value) / 100)
              }
          }
          .frame(height: 7)
        }
      }
    }
    .padding(14)
    .dashisGlassCard(cornerRadius: 16, fillOpacity: 0.62, shadowOpacity: 0.04)
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(DashisTheme.secondaryText(colorScheme))
      Spacer(minLength: 12)
      Text(value)
        .fontWeight(.semibold)
        .foregroundStyle(label == "Status" ? DashisTheme.statusColor(run.status) : DashisTheme.primaryText(colorScheme))
        .multilineTextAlignment(.trailing)
    }
    .font(DashisType.caption(12))
    .padding(12)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(DashisTheme.stroke(colorScheme))
        .frame(height: label == "Error budget" ? 0 : 1)
    }
  }

  private var pauseButton: some View {
    Button {
      monitorPaused.toggle()
    } label: {
      Label(monitorPaused ? "Resume monitor" : "Pause monitor",
            systemImage: monitorPaused ? "play.fill" : "pause.fill")
        .font(DashisType.body(13, .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
    .buttonStyle(.bordered)
  }
}
