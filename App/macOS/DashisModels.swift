import SwiftUI

enum DashisDashboardSection: String, CaseIterable, Identifiable {
  case overview
  case models
  case accounts
  case runs
  case alerts

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: "Overview"
    case .models: "Models"
    case .accounts: "Accounts"
    case .runs: "Runs"
    case .alerts: "Alerts"
    }
  }

  var symbolName: String {
    switch self {
    case .overview: "rectangle.3.group"
    case .models: "cpu"
    case .accounts: "lock.rectangle.stack"
    case .runs: "list.bullet.rectangle"
    case .alerts: "exclamationmark.triangle"
    }
  }
}

enum DashisChartMode: String, CaseIterable, Identifiable {
  case latency
  case quality

  var id: String { rawValue }

  var title: String {
    switch self {
    case .latency: "Latency"
    case .quality: "Quality"
    }
  }
}

enum DashisRunStatus: String {
  case healthy
  case watch
  case incident
}

struct DashisMetric: Identifiable {
  let id: String
  let title: String
  let value: String
  let delta: String
  let tone: DashisRunStatus
}

struct DashisRun: Identifiable, Hashable {
  let id: String
  let title: String
  let flow: String
  let model: String
  let status: DashisRunStatus
  let latency: Int
  let cost: Double
  let quality: Double
  let owner: String
  let guardrail: String
  let tokens: String
  let budget: String
  let signals: [DashisSignal]
}

struct DashisSignal: Hashable {
  let title: String
  let value: Int
  let tone: DashisRunStatus
}

struct DashisAccountStatus: Identifiable {
  let id: String
  let title: String
  let primary: String
  let secondary: String
  let usedPercent: Double
}

enum DashisSampleData {
  static let metrics = [
    DashisMetric(id: "latency", title: "Latency", value: "612ms", delta: "-8.4%", tone: .healthy),
    DashisMetric(id: "cost", title: "Cost", value: "$428", delta: "+3.1%", tone: .watch),
    DashisMetric(id: "quality", title: "Quality", value: "98.2%", delta: "+1.2%", tone: .healthy),
    DashisMetric(id: "incidents", title: "Incidents", value: "2", delta: "live", tone: .incident)
  ]

  static let latencySeries: [Double] = [720, 705, 660, 648, 630, 618, 612]
  static let qualitySeries: [Double] = [96.2, 96.8, 97.4, 97.2, 97.8, 98.0, 98.2]
  static let requestSeries: [Double] = [4850, 5260, 6010, 6420, 6900, 7340, 7680]

  static let accounts = [
    DashisAccountStatus(
      id: "codex",
      title: "Codex",
      primary: "Plan Pro",
      secondary: "2 reset credits",
      usedPercent: 42
    ),
    DashisAccountStatus(
      id: "openrouter",
      title: "OpenRouter",
      primary: "$74.75 remaining",
      secondary: "$25.75 used",
      usedPercent: 26
    )
  ]

  static let runs = [
    DashisRun(
      id: "run-1048",
      title: "Retrieval summary",
      flow: "support-rag",
      model: "gpt-4.1",
      status: .healthy,
      latency: 612,
      cost: 12.4,
      quality: 98.4,
      owner: "Ops",
      guardrail: "Groundedness",
      tokens: "18.4k",
      budget: "92%",
      signals: [
        DashisSignal(title: "Groundedness", value: 94, tone: .healthy),
        DashisSignal(title: "Refusal fit", value: 88, tone: .healthy),
        DashisSignal(title: "Latency budget", value: 79, tone: .healthy)
      ]
    ),
    DashisRun(
      id: "run-1047",
      title: "Invoice extraction",
      flow: "finance-agent",
      model: "gpt-4.1-mini",
      status: .watch,
      latency: 845,
      cost: 8.1,
      quality: 94.9,
      owner: "Finance",
      guardrail: "Schema match",
      tokens: "9.7k",
      budget: "76%",
      signals: [
        DashisSignal(title: "Schema match", value: 91, tone: .healthy),
        DashisSignal(title: "Latency budget", value: 63, tone: .watch),
        DashisSignal(title: "Retry rate", value: 18, tone: .watch)
      ]
    ),
    DashisRun(
      id: "run-1046",
      title: "Policy answer",
      flow: "legal-copilot",
      model: "o4-mini",
      status: .incident,
      latency: 1180,
      cost: 16.8,
      quality: 87.2,
      owner: "Risk",
      guardrail: "Citation required",
      tokens: "26.1k",
      budget: "41%",
      signals: [
        DashisSignal(title: "Citation coverage", value: 58, tone: .incident),
        DashisSignal(title: "Hallucination risk", value: 38, tone: .incident),
        DashisSignal(title: "Latency budget", value: 55, tone: .watch)
      ]
    ),
    DashisRun(
      id: "run-1045",
      title: "Search ranking",
      flow: "growth-eval",
      model: "gpt-4.1-mini",
      status: .healthy,
      latency: 488,
      cost: 4.9,
      quality: 97.6,
      owner: "Growth",
      guardrail: "Preference eval",
      tokens: "6.2k",
      budget: "96%",
      signals: [
        DashisSignal(title: "Preference win", value: 89, tone: .healthy),
        DashisSignal(title: "Latency budget", value: 91, tone: .healthy),
        DashisSignal(title: "Cost budget", value: 86, tone: .healthy)
      ]
    ),
    DashisRun(
      id: "run-1044",
      title: "Agent handoff",
      flow: "code-review",
      model: "gpt-4.1",
      status: .watch,
      latency: 702,
      cost: 19.3,
      quality: 95.1,
      owner: "Platform",
      guardrail: "Tool safety",
      tokens: "31.5k",
      budget: "69%",
      signals: [
        DashisSignal(title: "Tool safety", value: 99, tone: .healthy),
        DashisSignal(title: "Cost budget", value: 64, tone: .watch),
        DashisSignal(title: "Completion rate", value: 84, tone: .healthy)
      ]
    )
  ]
}
