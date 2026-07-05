import SwiftUI

struct DashisMetricGrid: View {
  let metrics: [DashisMetric]

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
      ForEach(metrics) { metric in
        DashisMetricCard(metric: metric)
      }
    }
  }
}

private struct DashisMetricCard: View {
  @Environment(\.colorScheme) private var colorScheme
  let metric: DashisMetric

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(metric.title)
        .font(DashisType.caption(12, .semibold))
        .foregroundStyle(DashisTheme.secondaryText(colorScheme))

      HStack(alignment: .firstTextBaseline) {
        Text(metric.value)
          .font(.system(size: 28, weight: .semibold, design: .rounded))
          .foregroundStyle(DashisTheme.primaryText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Spacer(minLength: 8)
        Text(metric.delta)
          .font(DashisType.caption(11, .bold))
          .foregroundStyle(DashisTheme.statusColor(metric.tone))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(DashisTheme.statusColor(metric.tone).opacity(0.12), in: Capsule())
      }
    }
    .padding(14)
    .frame(minHeight: 88, alignment: .topLeading)
    .dashisGlassCard(cornerRadius: 14)
  }
}

struct DashisChartPanel: View {
  @Environment(\.colorScheme) private var colorScheme
  @Binding var chartMode: DashisChartMode

  private var series: [Double] {
    chartMode == .latency ? DashisSampleData.latencySeries : DashisSampleData.qualitySeries
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        Text("Throughput")
          .font(DashisType.body(16, .semibold))
        Spacer()
        Picker("Chart metric", selection: $chartMode) {
          ForEach(DashisChartMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 168)
      }
      .padding(16)

      Divider()

      DashisMiniChart(lineSeries: series, barSeries: DashisSampleData.requestSeries)
        .frame(height: 286)
        .padding(16)
    }
    .dashisGlassCard(cornerRadius: 16)
  }
}

private struct DashisMiniChart: View {
  @Environment(\.colorScheme) private var colorScheme
  let lineSeries: [Double]
  let barSeries: [Double]

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let plot = CGRect(x: 36, y: 18, width: max(10, size.width - 56), height: max(10, size.height - 46))
      let points = linePoints(in: plot)

      ZStack(alignment: .topLeading) {
        grid(in: plot)
        bars(in: plot)
        Path { path in
          guard let first = points.first else { return }
          path.move(to: first)
          for point in points.dropFirst() {
            path.addLine(to: point)
          }
        }
        .stroke(DashisTheme.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
          Circle()
            .fill(DashisTheme.surface(colorScheme))
            .overlay(Circle().stroke(DashisTheme.accent, lineWidth: 2))
            .frame(width: 8, height: 8)
            .position(point)
        }

        Text("Mon")
          .font(DashisType.caption(10))
          .foregroundStyle(DashisTheme.tertiaryText(colorScheme))
          .position(x: plot.minX, y: plot.maxY + 16)
        Text("Thu")
          .font(DashisType.caption(10))
          .foregroundStyle(DashisTheme.tertiaryText(colorScheme))
          .position(x: plot.midX, y: plot.maxY + 16)
        Text("Sun")
          .font(DashisType.caption(10))
          .foregroundStyle(DashisTheme.tertiaryText(colorScheme))
          .position(x: plot.maxX, y: plot.maxY + 16)
      }
    }
  }

  private func linePoints(in rect: CGRect) -> [CGPoint] {
    guard let minValue = lineSeries.min(), let maxValue = lineSeries.max(), maxValue > minValue else { return [] }
    return lineSeries.enumerated().map { index, value in
      let x = rect.minX + rect.width * CGFloat(index) / CGFloat(Swift.max(lineSeries.count - 1, 1))
      let y = rect.maxY - rect.height * CGFloat((value - minValue) / (maxValue - minValue))
      return CGPoint(x: x, y: y)
    }
  }

  private func grid(in rect: CGRect) -> some View {
    Path { path in
      for tick in 0...3 {
        let y = rect.minY + rect.height * CGFloat(tick) / 3
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
      }
    }
    .stroke(DashisTheme.stroke(colorScheme), lineWidth: 1)
  }

  private func bars(in rect: CGRect) -> some View {
    let maxValue = barSeries.max() ?? 1
    let step = rect.width / CGFloat(max(barSeries.count, 1))

    return ForEach(Array(barSeries.enumerated()), id: \.offset) { index, value in
      let height = max(18, rect.height * 0.55 * CGFloat(value / maxValue))
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(DashisTheme.accent.opacity(0.12))
        .frame(width: max(18, step - 18), height: height)
        .position(x: rect.minX + step * (CGFloat(index) + 0.5), y: rect.maxY - height / 2)
    }
  }
}
