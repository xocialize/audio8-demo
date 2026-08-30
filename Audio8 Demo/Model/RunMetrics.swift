//  RunMetrics.swift
//  The measurement record for one synthesis. This is the app's actual product — the
//  audio is the by-product.
//
//  DESIGN RULE: every field here is either MEASURED or an input that was actually used.
//  Nothing is derived-and-stored where it could drift from its inputs (RTF is computed,
//  not persisted separately), and nothing is estimated. A field that could not be
//  measured on a given run is `nil`, never a plausible default — a fabricated number in
//  a metrics table is worse than a blank, because it survives into comparisons.

import DesignScaffold
import Foundation

/// Process + MLX memory readings around one run.
struct MemoryReading: Codable, Hashable, Sendable {
    /// MLX live tensor bytes (weights + in-flight intermediates).
    let mlxActiveBytes: UInt64
    /// MLX recycling pool.
    let mlxCacheBytes: UInt64
    /// MLX process-lifetime high-water of active + cache.
    let mlxPeakBytes: UInt64
    /// Real process footprint (mach `phys_footprint`).
    let physFootprintBytes: UInt64

    static let zero = MemoryReading(mlxActiveBytes: 0, mlxCacheBytes: 0,
                                    mlxPeakBytes: 0, physFootprintBytes: 0)
}

/// The sampling knobs actually applied to a run.
struct RunParameters: Codable, Hashable, Sendable {
    var temperature: Double
    var topP: Double
    var topK: Int
    var maxFrames: Int
    var greedy: Bool
    var seed: Int?

    /// The HF Space's defaults (app.py `generate_speech` signature). These are NOT the
    /// model card's defaults — the Space runs hotter and longer. Both are offered in the
    /// UI because "which defaults" is itself a thing worth A/B-ing.
    static let spaceDefaults = RunParameters(temperature: 0.8, topP: 0.95, topK: 50,
                                             maxFrames: 1024, greedy: false, seed: nil)

    /// The upstream model card / generation_config.json defaults.
    static let modelCardDefaults = RunParameters(temperature: 0.7, topP: 0.9, topK: 50,
                                                 maxFrames: 512, greedy: false, seed: nil)

    /// Deterministic decoding — the configuration the port's S2 gate proves token-exact
    /// against the PyTorch reference. The right choice for regression comparison.
    static let deterministic = RunParameters(temperature: 0.7, topP: 0.9, topK: 50,
                                             maxFrames: 512, greedy: true, seed: 1234)

    // Validation ranges lifted from the Space's server-side checks so the app rejects the
    // same inputs the reference implementation would.
    static let temperatureRange: ClosedRange<Double> = 0.01...2.0
    static let topPRange: ClosedRange<Double> = 0.01...1.0
    static let topKRange: ClosedRange<Int> = 1...200
    static let maxFramesRange: ClosedRange<Int> = 32...2048
    static let maxCharacters = 1000

    /// Slider-facing mirrors of the integer ranges (SwiftUI sliders are Double-valued).
    static let topKSliderRange: ClosedRange<Double> = 1...200
    static let maxFramesSliderRange: ClosedRange<Double> = 32...2048
}

/// How the reference voice was supplied.
enum VoiceSource: Codable, Hashable, Sendable {
    case corpus(id: String)
    case custom(filename: String)
    case defaultVoice

    var label: String {
        switch self {
        case .corpus(let id): VoiceCorpus.voice(id: id)?.name ?? id
        case .custom(let filename): filename
        case .defaultVoice: "Model default"
        }
    }
}

/// One completed (or failed) synthesis.
struct RunRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date

    /// Which checkpoint produced this run. Recorded per record rather than held as app-wide
    /// state so a history or an exported sweep stays meaningful across a model switch — a
    /// table of RTFs that cannot say which model each row came from is not a comparison.
    let checkpoint: Audio8Checkpoint

    // Inputs
    let voice: VoiceSource
    let promptLabel: String?
    let text: String
    let referenceTranscript: String?
    let parameters: RunParameters

    // Timing (seconds). `loadSeconds` is nil when the model was already resident — that
    // distinction matters and must not be flattened to 0.
    let loadSeconds: Double?
    let runSeconds: Double

    // Output
    let frames: Int
    let sampleCount: Int
    let sampleRate: Int
    /// RMS level. `-.infinity` for digital silence.
    let rmsDBFS: Double
    let peakDBFS: Double

    // Memory
    let memoryBefore: MemoryReading
    let memoryAfter: MemoryReading
    /// Peak during the run, minus the resident floor before it.
    let transientBytes: UInt64

    /// Set when the run threw. A failed run is still a record — knowing what fails, and
    /// how fast, is part of the debugging surface.
    let failure: String?

    // MARK: Derived

    var duration: Double { sampleRate > 0 ? Double(sampleCount) / Double(sampleRate) : 0 }
    /// < 1 is faster than realtime.
    var realTimeFactor: Double { duration > 0 ? runSeconds / duration : 0 }
    /// Frames per second of wall clock — the AR rollout's throughput.
    var framesPerSecond: Double { runSeconds > 0 ? Double(frames) / runSeconds : 0 }
    var succeeded: Bool { failure == nil }

    /// Level classification driving the UI color and the "is this actually audio?" check.
    enum Level: String, Codable { case silent, low, healthy, clipping }
    var level: Level {
        if rmsDBFS <= Tokens.Audio.silenceFloorDBFS { return .silent }
        if peakDBFS >= Tokens.Audio.clippingCeilingDBFS { return .clipping }
        return rmsDBFS >= Tokens.Audio.healthyFloorDBFS ? .healthy : .low
    }
}

// MARK: - Aggregates

/// Summary across a set of runs. Reports median alongside mean: with a handful of runs a
/// single cold-start outlier drags the mean somewhere unrepresentative, and the first run
/// after a load is always the outlier.
struct RunAggregate: Sendable {
    let count: Int
    let meanRTF: Double
    let medianRTF: Double
    let bestRTF: Double
    let worstRTF: Double
    let meanFramesPerSecond: Double
    let maxTransientBytes: UInt64
    let silentCount: Int
    let failureCount: Int

    init(records: [RunRecord]) {
        let ok = records.filter { $0.succeeded && $0.duration > 0 }
        let rtfs = ok.map(\.realTimeFactor).sorted()
        count = records.count
        meanRTF = rtfs.isEmpty ? 0 : rtfs.reduce(0, +) / Double(rtfs.count)
        medianRTF = rtfs.isEmpty ? 0 : rtfs[rtfs.count / 2]
        bestRTF = rtfs.first ?? 0
        worstRTF = rtfs.last ?? 0
        let fps = ok.map(\.framesPerSecond)
        meanFramesPerSecond = fps.isEmpty ? 0 : fps.reduce(0, +) / Double(fps.count)
        maxTransientBytes = records.map(\.transientBytes).max() ?? 0
        silentCount = ok.filter { $0.level == .silent }.count
        failureCount = records.filter { !$0.succeeded }.count
    }
}

// MARK: - Export

extension Array where Element == RunRecord {
    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Flat CSV for spreadsheet/regression diffing across builds.
    func exportCSV() -> String {
        let header = [
            "started_at", "voice", "prompt", "chars", "temperature", "top_p", "top_k",
            "max_frames", "greedy", "seed", "load_s", "run_s", "frames", "duration_s",
            "rtf", "frames_per_s", "rms_dbfs", "peak_dbfs", "level",
            "transient_mb", "peak_mlx_mb", "phys_mb", "failure",
        ].joined(separator: ",")

        let formatter = ISO8601DateFormatter()
        func mb(_ bytes: UInt64) -> String { String(format: "%.0f", Double(bytes) / 1_048_576) }
        func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }

        let rows = map { r in
            [
                formatter.string(from: r.startedAt),
                esc(r.voice.label),
                esc(r.promptLabel ?? "custom"),
                String(r.text.count),
                String(format: "%.3f", r.parameters.temperature),
                String(format: "%.3f", r.parameters.topP),
                String(r.parameters.topK),
                String(r.parameters.maxFrames),
                String(r.parameters.greedy),
                r.parameters.seed.map(String.init) ?? "",
                r.loadSeconds.map { String(format: "%.3f", $0) } ?? "",
                String(format: "%.3f", r.runSeconds),
                String(r.frames),
                String(format: "%.3f", r.duration),
                String(format: "%.4f", r.realTimeFactor),
                String(format: "%.2f", r.framesPerSecond),
                r.rmsDBFS.isFinite ? String(format: "%.2f", r.rmsDBFS) : "-inf",
                r.peakDBFS.isFinite ? String(format: "%.2f", r.peakDBFS) : "-inf",
                r.level.rawValue,
                mb(r.transientBytes),
                mb(r.memoryAfter.mlxPeakBytes),
                mb(r.memoryAfter.physFootprintBytes),
                esc(r.failure ?? ""),
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }
}
