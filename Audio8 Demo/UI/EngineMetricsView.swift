//  EngineMetricsView.swift
//  Engine-level telemetry — the numbers that belong to MLXEngine rather than to one run.
//
//  The panel exists for one job beyond curiosity: comparing what the package DECLARES in
//  its manifest against what this machine actually measures. A stale declaration is not
//  cosmetic — the governor admits and evicts on it, so an under-declared activation peak
//  silently shrinks admissibility for every other model, and an over-declared one wastes
//  budget. Declared-vs-measured is therefore shown as a first-class row with a verdict.

import MLXAudio8TTS
import MLXServeCore
import MLXToolKit
import SwiftUI

struct EngineMetricsView: View {
    @Bindable var bench: Audio8Bench
    @State private var snapshot: MemorySnapshot?
    @State private var pool: GPUPoolSnapshot?

    /// What the package manifest declares for the bf16 variant.
    private var declaredResident: UInt64 { Audio8Package.manifest.requirements.footprints
        .first { $0.quant == .bf16 }?.residentBytes ?? 0 }
    private var declaredActivation: UInt64 { Audio8Package.manifest.requirements.footprints
        .first { $0.quant == .bf16 }?.peakActivationBytes ?? 0 }

    /// The worst transient observed this session — the number the manifest should reflect.
    private var measuredActivation: UInt64 { bench.aggregate.maxTransientBytes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                Text("Engine-level readings, refreshed on demand. These are what MLXEngine uses "
                     + "to admit and evict models — not per-run performance.")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                governorSection
                poolSection
                declarationSection

                Button {
                    refresh()
                } label: { Label("Refresh", systemImage: Tokens.Symbol.metrics) }
            }
            .padding(Tokens.Space.xl)
        }
        .onAppear { refresh() }
        .onChange(of: bench.records.count) { refresh() }
    }

    // MARK: Governor

    private var governorSection: some View {
        Section(title: "Memory governor", systemImage: Tokens.Symbol.memory) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Tokens.Layout.metricTileMinWidth),
                                         spacing: Tokens.Space.s)],
                      spacing: Tokens.Space.s) {
                MetricTile(value: snapshot.map { Double.formatBytes($0.budgetBytes) } ?? "—",
                           label: "Budget", caption: "0.7 × device")
                MetricTile(value: snapshot.map { Double.formatBytes($0.residentBytes) } ?? "—",
                           label: "Charged resident",
                           caption: "declared, not measured")
                MetricTile(value: snapshot.map { Double.formatBytes($0.transientReserveBytes) } ?? "—",
                           label: "Transient reserve",
                           caption: "max activation across residents")
                MetricTile(value: snapshot.map { Double.formatBytes($0.availableBytes) } ?? "—",
                           label: "Available",
                           caption: "budget − resident − reserve")
                MetricTile(value: snapshot?.realResidentBytes.map { Double.formatBytes($0) } ?? "—",
                           label: "Real phys", caption: "actual process footprint")
                MetricTile(value: (snapshot?.underRealPressure ?? false) ? "YES" : "no",
                           label: "Under pressure",
                           emphasis: (snapshot?.underRealPressure ?? false)
                               ? Tokens.Color.failure : Tokens.Color.label,
                           caption: "R-MEM-1 real-pressure")
            }
        }
    }

    // MARK: GPU pool

    private var poolSection: some View {
        Section(title: "GPU buffer pool", systemImage: Tokens.Symbol.engine) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                LabeledContent("Active (live tensors)",
                               value: pool.map { Double.formatBytes($0.activeBytes) } ?? "—")
                LabeledContent("Cache (recycling pool)",
                               value: pool.map { Double.formatBytes($0.cacheBytes) } ?? "—")
                LabeledContent("Peak (process lifetime)",
                               value: pool.map { Double.formatBytes($0.peakBytes) } ?? "—")
                LabeledContent("Cache limit (effective)",
                               value: pool.map { Double.formatBytes($0.cacheLimitBytes) } ?? "—")
                Text("The engine bounds this pool by default. An unbounded pool — what a bare "
                     + "CLI harness gets — is a different allocator regime, so numbers measured "
                     + "here and there are not automatically comparable.")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Tokens.Space.xs)
            }
            .font(Tokens.Font.metricInline)
            .padding(Tokens.Space.m)
            .cardSurface()
        }
    }

    // MARK: Declaration check

    private var declarationSection: some View {
        Section(title: "Manifest declaration vs measured", systemImage: Tokens.Symbol.benchmark) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                declarationRow(
                    label: "Resident floor",
                    declared: declaredResident,
                    measured: bench.residentFloorBytes,
                    // The floor should sit at or just under the declaration; a measured floor
                    // ABOVE it means the governor is under-charging this package.
                    ok: bench.residentFloorBytes == 0 || bench.residentFloorBytes <= declaredResident)
                declarationRow(
                    label: "Activation peak",
                    declared: declaredActivation,
                    measured: measuredActivation,
                    ok: measuredActivation == 0 || measuredActivation <= declaredActivation)

                if measuredActivation > 0 && measuredActivation > declaredActivation {
                    Text("Measured activation exceeds the declaration. The governor reserves the "
                         + "declared value, so real runs can overshoot the budget it thinks it has "
                         + "— update peakActivationBytes in the package manifest.")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.failure)
                        .fixedSize(horizontal: false, vertical: true)
                } else if measuredActivation > 0 {
                    let headroom = Double(declaredActivation - measuredActivation) / 1_048_576
                    Text(String(format: "Declaration holds with %.0f MB of headroom over the "
                                + "worst run this session.", headroom))
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Run the sweep first — a single short utterance under-reads the activation "
                     + "peak, which scales with utterance length.")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.tertiaryLabel)
            }
            .padding(Tokens.Space.m)
            .cardSurface()
        }
    }

    private func declarationRow(label: String, declared: UInt64,
                                measured: UInt64, ok: Bool) -> some View {
        HStack {
            Text(label)
                .font(Tokens.Font.metricInline)
            Spacer()
            Text("declared \(Double.formatBytes(declared))")
                .font(Tokens.Font.metricInline)
                .foregroundStyle(Tokens.Color.secondaryLabel)
            Text("·")
                .foregroundStyle(Tokens.Color.tertiaryLabel)
            Text(measured == 0 ? "measured —" : "measured \(Double.formatBytes(measured))")
                .font(Tokens.Font.metricInline)
                .foregroundStyle(measured == 0 ? Tokens.Color.tertiaryLabel
                                 : (ok ? Tokens.Color.ready : Tokens.Color.failure))
        }
    }

    private func refresh() {
        Task {
            snapshot = await bench.engine.memory
            pool = bench.engine.gpuPoolSnapshot()
        }
    }
}
