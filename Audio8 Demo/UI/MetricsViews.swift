//  MetricsViews.swift
//  The measurement surfaces: live panel, session history, and the sweep runner.
//
//  A note on what is deliberately NOT shown as a single number: memory is always
//  reported as MLX-accounted AND process phys side by side, because they disagree by a
//  large factor and picking one hides the disagreement. Likewise a run with no measured
//  load shows "—", never 0.

import DesignScaffold
import DesignScaffoldMetrics
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Live panel

struct LiveMetricsPanel: View {
    @Bindable var bench: Audio8Bench

    private var last: RunRecord? { bench.records.last }

    var body: some View {
        LabeledSection(title: "Measurements", systemImage: Tokens.Symbol.benchmark) {
            MetricGrid {
                MetricTile(last.map { String(format: "%.2f", $0.realTimeFactor) } ?? "—",
                           label: "Real-time factor",
                           caption: "< 1.0 is faster than realtime",
                           emphasis: rtfColor).carded()
                MetricTile(last.map { String(format: "%.2f", $0.runSeconds) } ?? "—",
                           label: "Run", unit: "s").carded()
                MetricTile(last.map { String(format: "%.2f", $0.duration) } ?? "—",
                           label: "Audio", unit: "s").carded()
                MetricTile(last.map { String($0.frames) } ?? "—",
                           label: "Frames",
                           caption: last.map { String(format: "%.1f fps", $0.framesPerSecond) }).carded()
                MetricTile(bench.loadSeconds.map { String(format: "%.2f", $0) } ?? "—",
                           label: "Model load", unit: "s",
                           caption: bench.loadSeconds == nil ? "already resident" : nil).carded()
                MetricTile(Double.formatBytes(bench.residentFloorBytes),
                           label: "Resident floor",
                           caption: "post-load, pre-run").carded()
                MetricTile(last.map { Double.formatBytes($0.transientBytes) } ?? "—",
                           label: "Transient",
                           caption: "peak − floor").carded()
                MetricTile(last.map { Double.formatBytes($0.memoryAfter.physFootprintBytes) } ?? "—",
                           label: "Process phys",
                           caption: "MLX under-reads vs this").carded()
            }
        }
    }

    private var rtfColor: Color {
        guard let rtf = last?.realTimeFactor, rtf > 0 else { return Tokens.Color.label }
        return rtf < 1 ? Tokens.Color.ready : Tokens.Color.working
    }
}

// MARK: - History

struct HistoryView: View {
    @Bindable var bench: Audio8Bench
    @State private var selection: RunRecord.ID?

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()
            if bench.records.isEmpty {
                ContentUnavailableView("No runs yet",
                                       systemImage: Tokens.Symbol.history,
                                       description: Text("Generate speech or run the sweep to "
                                                         + "collect measurements."))
            } else {
                table
            }
        }
    }

    private var summaryBar: some View {
        let aggregate = bench.aggregate
        return HStack(spacing: Tokens.Space.l) {
            summaryItem("Runs", "\(aggregate.count)")
            summaryItem("Median RTF", String(format: "%.2f", aggregate.medianRTF))
            summaryItem("Best", String(format: "%.2f", aggregate.bestRTF))
            summaryItem("Worst", String(format: "%.2f", aggregate.worstRTF))
            summaryItem("Mean fps", String(format: "%.1f", aggregate.meanFramesPerSecond))
            summaryItem("Max transient", Double.formatBytes(aggregate.maxTransientBytes))
            if aggregate.silentCount > 0 {
                summaryItem("Silent", "\(aggregate.silentCount)", tint: Tokens.Color.failure)
            }
            if aggregate.failureCount > 0 {
                summaryItem("Failed", "\(aggregate.failureCount)", tint: Tokens.Color.failure)
            }
            Spacer()
            Button {
                export(.json)
            } label: { Label("JSON", systemImage: Tokens.Symbol.export) }
            Button {
                export(.csv)
            } label: { Label("CSV", systemImage: Tokens.Symbol.export) }
            Button {
                bench.clearRecords()
            } label: { Label("Clear", systemImage: Tokens.Symbol.clear) }
                .disabled(bench.records.isEmpty)
        }
        .padding(Tokens.Space.m)
    }

    private func summaryItem(_ label: String, _ value: String,
                             tint: Color = Tokens.Color.label) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Tokens.Font.metricInline)
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(Tokens.Font.metricLabel)
                .foregroundStyle(Tokens.Color.secondaryLabel)
        }
    }

    private var table: some View {
        Table(bench.records.reversed(), selection: $selection) {
            TableColumn("Time") { r in
                Text(r.startedAt.formatted(date: .omitted, time: .standard))
                    .font(Tokens.Font.metricInline)
            }
            .width(80)
            TableColumn("Voice") { r in
                Text(r.voice.label).font(Tokens.Font.metricInline)
            }
            .width(90)
            TableColumn("Prompt") { r in
                Text(r.promptLabel ?? "custom").font(Tokens.Font.metricInline)
            }
            .width(70)
            TableColumn("RTF") { r in
                Text(String(format: "%.2f", r.realTimeFactor))
                    .font(Tokens.Font.metricInline)
                    .foregroundStyle(r.realTimeFactor < 1 ? Tokens.Color.ready : Tokens.Color.working)
            }
            .width(50)
            // Run and audio seconds share a column: SwiftUI's Table tops out at 10
            // columns, and the pair reads better together anyway (RTF is their ratio).
            TableColumn("Run / audio s") { r in
                Text(String(format: "%.2f / %.2f", r.runSeconds, r.duration))
                    .font(Tokens.Font.metricInline)
            }
            .width(92)
            TableColumn("Frames") { r in
                Text("\(r.frames)").font(Tokens.Font.metricInline)
            }
            .width(56)
            TableColumn("Level") { r in
                Text(r.rmsDBFS.isFinite ? String(format: "%.1f", r.rmsDBFS) : "−∞")
                    .font(Tokens.Font.metricInline)
                    .foregroundStyle(r.level == .healthy ? Tokens.Color.label : Tokens.Color.levelSilent)
            }
            .width(56)
            TableColumn("Transient") { r in
                Text(Double.formatBytes(r.transientBytes)).font(Tokens.Font.metricInline)
            }
            .width(74)
            TableColumn("Temp") { r in
                Text(String(format: "%.2f", r.parameters.temperature)).font(Tokens.Font.metricInline)
            }
            .width(46)
            TableColumn("Status") { r in
                Text(r.failure ?? "ok")
                    .font(Tokens.Font.metricInline)
                    .foregroundStyle(r.succeeded ? Tokens.Color.secondaryLabel : Tokens.Color.failure)
                    .lineLimit(1)
            }
        }
        .font(Tokens.Font.metricInline)
    }

    private enum ExportFormat { case json, csv }

    private func export(_ format: ExportFormat) {
        let panel = NSSavePanel()
        let stamp = Int(Date().timeIntervalSince1970)
        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "audio8-metrics-\(stamp).json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "audio8-metrics-\(stamp).csv"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch format {
        case .json:
            if let data = try? bench.records.exportJSON() { try? data.write(to: url) }
        case .csv:
            try? bench.records.exportCSV().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Sweep

/// The regression runner: fixed corpus × fixed prompts × deterministic decoding, so two
/// builds produce directly comparable tables.
struct SweepView: View {
    @Bindable var bench: Audio8Bench

    @State private var selectedVoices: Set<String> = Set(VoiceCorpus.all.map(\.id))
    @State private var selectedPrompts: Set<String> = Set(BenchmarkPrompt.suite.map(\.id))
    @State private var useDeterministic = true
    @State private var isRunning = false

    private var runCount: Int { selectedVoices.count * selectedPrompts.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                Text("Runs every selected voice against every selected prompt. Deterministic "
                     + "decoding fixes the sampler so differences between builds are attributable "
                     + "to the port, not to sampling noise.")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledSection(title: "Voices", systemImage: Tokens.Symbol.voice) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Tokens.Space.s)],
                              spacing: Tokens.Space.s) {
                        ForEach(VoiceCorpus.all) { voice in
                            Toggle(isOn: Binding(
                                get: { selectedVoices.contains(voice.id) },
                                set: { on in
                                    if on { selectedVoices.insert(voice.id) }
                                    else { selectedVoices.remove(voice.id) }
                                })) {
                                    Text("\(voice.name) · \(voice.locale)")
                                        .font(Tokens.Font.caption)
                                }
                        }
                    }
                }

                LabeledSection(title: "Prompts", systemImage: Tokens.Symbol.generate) {
                    VStack(alignment: .leading) {
                        ForEach(BenchmarkPrompt.suite) { prompt in
                            Toggle(isOn: Binding(
                                get: { selectedPrompts.contains(prompt.id) },
                                set: { on in
                                    if on { selectedPrompts.insert(prompt.id) }
                                    else { selectedPrompts.remove(prompt.id) }
                                })) {
                                    Text("\(prompt.label) — \(prompt.text.prefix(60))…")
                                        .font(Tokens.Font.caption)
                                        .lineLimit(1)
                                }
                        }
                    }
                }

                Toggle("Deterministic decoding (recommended for comparison)",
                       isOn: $useDeterministic)
                    .font(Tokens.Font.caption)

                HStack(spacing: Tokens.Space.m) {
                    Button {
                        Task { await runSweep() }
                    } label: {
                        Label(isRunning ? "Running…" : "Run \(runCount) syntheses",
                              systemImage: Tokens.Symbol.benchmark)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || runCount == 0 || bench.engineState.isBusy)

                    if isRunning {
                        ProgressView().controlSize(.small)
                        Text("\(bench.records.count) done · \(bench.liveFrames) frames")
                            .font(Tokens.Font.metricInline)
                            .foregroundStyle(Tokens.Color.secondaryLabel)
                    }
                }
            }
            .padding(Tokens.Space.xl)
        }
    }

    private func runSweep() async {
        isRunning = true
        defer { isRunning = false }
        let voices = VoiceCorpus.all.filter { selectedVoices.contains($0.id) }
        let prompts = BenchmarkPrompt.suite.filter { selectedPrompts.contains($0.id) }
        await bench.runSweep(voices: voices,
                             prompts: prompts,
                             parameters: useDeterministic ? .deterministic : .spaceDefaults)
    }
}
