//  RootView.swift
//  Window shell: sidebar navigation, engine status, and the model-state affordance.
//
//  ModelStateView / EngineSettingsView come from MLXEngineUI rather than being rebuilt —
//  they already render download fraction → loading → ready, which is the difference
//  between a real first-run affordance and a dead spinner.

import DesignScaffold
import MLXEngineUI
import MLXServeCore
import MLXToolKit
import SwiftUI

struct RootView: View {
    @Bindable var bench: Audio8Bench
    @State private var pane: Pane = .synthesize

    enum Pane: String, CaseIterable, Identifiable {
        case synthesize = "Synthesize"
        case sweep = "Sweep"
        case longForm = "Long-form"
        case history = "History"
        case engine = "Engine"
        case settings = "Settings"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .synthesize: Tokens.Symbol.generate
            case .sweep: Tokens.Symbol.benchmark
            case .longForm: Tokens.Symbol.export
            case .history: Tokens.Symbol.history
            case .engine: Tokens.Symbol.memory
            case .settings: Tokens.Symbol.settings
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .toolbar { toolbarContent }
        }
        .navigationTitle("Audio8 TTS — reference & metrics")
        .frame(minWidth: Tokens.Layout.minWindowWidth,
               minHeight: Tokens.Layout.minWindowHeight)
        .task {
            // Bootstrap behind the progress affordance rather than inside the user's first
            // Generate, so the multi-GB load is visible instead of looking like a hang.
            await bench.bootstrap()
        }
        // The store panel writes `appliedPath` when the user grants a folder; a change
        // there has to re-register (useModelStore only binds packages registered after
        // it), which is what this hook drives.
        .onChange(of: bench.storage.appliedPath) {
            Task { await bench.storeChangedIfNeeded() }
        }
        // Watching the GRANT as well as the path: granting the folder the app already
        // had as its default changes only this, and that is the common case.
        .onChange(of: bench.storage.resolvedModelsDirectory) {
            Task { await bench.storeChangedIfNeeded() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(Pane.allCases, selection: $pane) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
            }
            .listStyle(.sidebar)

            Divider()

            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                CheckpointPicker(bench: bench)
                Divider()
                ModelStateView(monitor: bench.engine.preparation, capability: .tts)
                EngineStatusPill(state: bench.engineState)
                if let error = bench.lastError {
                    Text(error)
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.failure)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Tokens.Space.m)
        }
        .navigationSplitViewColumnWidth(Tokens.Layout.sidebarWidth)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .synthesize: SynthesizeView(bench: bench)
        case .sweep: SweepView(bench: bench)
        case .longForm: LongFormView(bench: bench)
        case .history: HistoryView(bench: bench)
        case .engine: EngineMetricsView(bench: bench)
        case .settings: settings
        }
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                Text("Weights are shared with the rest of the fleet through the models folder "
                     + "below. Pointing every app at one folder is what stops each of them "
                     + "downloading its own multi-gigabyte copy.")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                EngineSettingsView(storage: bench.storage)

                LabeledSection(title: "Model", systemImage: Tokens.Symbol.engine) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        LabeledContent("Package", value: "Audio8-TTS-Preview-0.6b")
                        LabeledContent("Weights", value: "mlx-community/Audio8-TTS-Preview-0.6b-bf16")
                        LabeledContent("Sample rate", value: "44 100 Hz mono")
                        LabeledContent("Frame", value: "2048 samples ≈ 46 ms")
                    }
                    .font(Tokens.Font.metricInline)
                    .padding(Tokens.Space.m)
                    .cardSurface()
                }

                HStack(spacing: Tokens.Space.m) {
                    Button {
                        Task { await bench.loadModel() }
                    } label: {
                        Label(bench.engineState == .needsDownload
                              ? "Download & load (\(bench.checkpoint.approximateDownloadDescription))"
                              : "Load model",
                              systemImage: Tokens.Symbol.engine)
                    }
                    .disabled(bench.engineState == .ready || bench.engineState.isBusy
                              || bench.engineState == .needsFolder)
                    Button {
                        Task { await bench.evict() }
                    } label: { Label("Evict", systemImage: Tokens.Symbol.clear) }
                        .disabled(bench.engineState != .ready)
                    Button {
                        Task { await bench.bootstrap() }
                    } label: { Label("Re-register", systemImage: Tokens.Symbol.engine) }
                        .disabled(bench.engineState.isBusy)
                        .help("Re-apply the models folder and re-register the package.")
                }

                if bench.engineState == .needsFolder {
                    Text("Choose the folder above that holds your MLX models, then this "
                         + "becomes available.")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.working)
                }
            }
            .padding(Tokens.Space.xl)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            EngineStatusPill(state: bench.engineState)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await bench.loadModel() }
            } label: {
                Image(systemName: Tokens.Symbol.engine)
            }
            .help(bench.engineState == .needsDownload ? "Download and load the weights"
                                                      : "Load the model")
            .disabled(bench.engineState == .ready || bench.engineState.isBusy
                      || bench.engineState == .needsFolder)
        }
    }
}


/// Which checkpoint the app is pointed at.
///
/// Sits directly above `ModelStateView` because it determines what that state is ABOUT —
/// switching evicts one model and prepares the other, so the two belong together.
///
/// The subtitle is not decoration. Both checkpoints clone voices and the smaller one is
/// newer, so "0.1B" reads as an upgrade unless the tradeoff is stated: it is the footprint
/// option, and it clones less faithfully. The declared resident floor is shown for the same
/// reason — the saving is much smaller than the parameter counts suggest, because both share
/// the same 1.35 GB codec.
struct CheckpointPicker: View {
    @Bindable var bench: Audio8Bench

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Checkpoint")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.secondaryLabel)

            Picker("Checkpoint", selection: Binding(
                get: { bench.checkpoint },
                set: { next in Task { await bench.select(next) } }
            )) {
                ForEach(Audio8Checkpoint.allCases) { checkpoint in
                    Text(checkpoint.shortName).tag(checkpoint)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(bench.engineState.isBusy)

            Text(bench.checkpoint.subtitle)
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            Text("declares \(ByteCountFormatter.string(fromByteCount: Int64(bench.checkpoint.declaredResidentBytes), countStyle: .memory)) resident")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.tertiaryLabel)
        }
    }
}
