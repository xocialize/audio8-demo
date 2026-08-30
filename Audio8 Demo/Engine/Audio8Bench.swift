//  Audio8Bench.swift
//  The app model: owns ONE MLXServeEngine, wires the shared model store, registers
//  Audio8Package, and turns each synthesis into a measured `RunRecord`.
//
//  Follows the mlxengine-implementation golden path, in order:
//    1. own one engine with a real governor budget
//    2. stand up the model store BEFORE registering (useModelStore only affects
//       packages registered after it)
//    3. register
//    4. surface preparation via the engine's monitor
//    5. prepare before first run
//
//  MEASUREMENT NOTE: the resident floor is read AFTER prepare() and BEFORE the first
//  run, because clearCache() frees pool buffers but not referenced weights — measuring
//  post-run would fold the transient into the floor. The transient is peak-minus-floor,
//  which is what `QuantFootprint.peakActivationBytes` means.

import AVFoundation
import Foundation
import MLX
import MLXAudio8TTS
import MLXEngineUI
import MLXServeCore
import MLXToolKit
import Observation
import SwiftUI
import AudioPolishKit
import TTSOrchestratorKit

@MainActor
@Observable
final class Audio8Bench {

    // MARK: Engine

    /// One instance for the app's lifetime. 0.7 of device memory is the house default —
    /// enough headroom for the codec's decode transient on top of the resident weights.
    let engine = MLXServeEngine(governor: .forDevice(.current(), fraction: 0.7))

    /// The shared model store. Defaults to the engine's standard location; point it at a
    /// shared folder in Settings so weights are not re-downloaded per app. Deliberately NOT a
    /// machine-specific path — this app is meant to build and run for anyone.
    let storage = ModelStorageModel()

    /// Which checkpoint the app is currently pointed at. Both are registered; this decides
    /// which one `prepare`/`run`/`evict` address.
    private(set) var checkpoint: Audio8Checkpoint = .preview06b

    /// One `PackageID` per checkpoint. The engine supports several packages behind one
    /// capability, so both are registered up front and switching is a `prepare()` on the
    /// other id — no re-registration, and the unselected one simply stays unloaded.
    private(set) var packageIDs: [Audio8Checkpoint: PackageID] = [:]

    /// The id every engine call in this file routes through.
    var packageID: PackageID? { packageIDs[checkpoint] }
    /// What the CURRENT registration was bound to. BOTH are tracked deliberately: the
    /// user-visible path string AND the resolved security-scoped grant.
    ///
    /// Tracking only the path (the obvious choice, and the first cut here) has a hole this
    /// app walks straight into: the default path is pre-seeded to the shared fleet store,
    /// so when the user grants exactly that folder the STRING never changes — only the
    /// grant does, nil → URL. The re-register then never fires and "Load model" stays
    /// disabled forever with the folder correctly granted. The grant is the thing that
    /// actually gates materialization, so it is the thing to watch.
    private var boundStorePath: String?
    private var boundStoreRoot: URL?
    private(set) var engineState: EngineState = .idle
    private(set) var lastError: String?

    /// `needsFolder` and `needsDownload` are deliberately NOT failures — they are the two
    /// legitimate first-run stops, each with an obvious next action. Folding them into
    /// `.failed` (the first cut of this file did) turns a normal first launch into what
    /// looks like a broken app.
    enum EngineState: Equatable {
        case idle, registering, needsFolder, needsDownload, preparing, ready, working
        case failed(String)

        var label: String {
            switch self {
            case .idle: "Not loaded"
            case .registering: "Registering"
            case .needsFolder: "Choose a models folder"
            case .needsDownload: "Weights not downloaded"
            case .preparing: "Loading model"
            case .ready: "Ready"
            case .working: "Generating"
            case .failed(let why): "Failed — \(why)"
            }
        }
        var isBusy: Bool { self == .registering || self == .preparing || self == .working }
    }

    // MARK: Measurement state

    /// Every run this session, newest last.
    private(set) var records: [RunRecord] = []
    /// Live frame counter during a run, from the package's RunProgress reports.
    private(set) var liveFrames: Int = 0
    /// Resident floor measured right after load, before any run.
    private(set) var residentFloorBytes: UInt64 = 0
    private(set) var loadSeconds: Double?
    /// Consumed by the next run, then cleared — a load only happens once.
    private var pendingLoadSeconds: Double?

    var aggregate: RunAggregate { RunAggregate(records: records) }

    // MARK: Playback

    private var player: AVAudioPlayer?
    private(set) var lastAudioURL: URL?

    // MARK: - Lifecycle

    /// Step 2 → 3 → 5 of the golden path.
    ///
    /// Re-entrant on purpose, and this is the FIRST-RUN path that matters: on a fresh
    /// install no models folder has been granted yet, so registration happens with no
    /// store, `prepare()` fails with "no models root set", and the user then grants the
    /// folder in Settings. Two things have to be true for that recovery to work, and
    /// both were wrong in the first cut of this method:
    ///
    ///  1. **A failed state must be retryable.** Guarding on `.idle` alone meant the
    ///     post-grant "Load model" button did nothing at all.
    ///  2. **Granting the folder later must RE-REGISTER.** `useModelStore` only affects
    ///     packages registered *after* it, so applying the store to an already-registered
    ///     package is a no-op — the package keeps its store-less configuration and keeps
    ///     failing with the same message. Re-registering under the same `PackageID`
    ///     replaces the entry (and evicts any stale resident), which is the engine's
    ///     supported way to re-point it.
    func bootstrap() async {
        guard !engineState.isBusy else { return }
        lastError = nil
        engineState = .registering
        boundStorePath = storage.appliedPath
        boundStoreRoot = storage.resolvedModelsDirectory

        // Always applied, even with a nil root — ModelStore accepts an optional, and
        // calling it unconditionally keeps store state and registration state in lockstep.
        await engine.useModelStore(ModelStore(root: storage.resolvedModelsDirectory))

        do {
            // Both checkpoints, every time. Same id ⇒ replaces the previous registration
            // rather than stacking one, which is what makes a folder change re-registerable.
            packageIDs[.preview06b] = try await engine.register(
                PackageRegistration.of(Audio8Package.self),
                configuration: Audio8Configuration(),
                id: packageIDs[.preview06b])
            packageIDs[.preview01b] = try await engine.register(
                PackageRegistration.of(Audio8MiniPackage.self),
                configuration: Audio8MiniConfiguration(),
                id: packageIDs[.preview01b])
        } catch {
            let message = String(describing: error)
            engineState = .failed(message)
            lastError = message
            return
        }

        // Two legitimate stops before loading, each surfaced as its own state so the UI
        // can offer the right next action instead of an error.
        guard storage.resolvedModelsDirectory != nil else {
            engineState = .needsFolder
            return
        }
        if await engine.needsDownload(.tts, package: packageID) {
            // Gated on explicit consent rather than pulled silently on launch. The size
            // differs per checkpoint, so the prompt reads it from the selection.
            engineState = .needsDownload
            return
        }
        await loadModel()
    }

    /// Point the app at the other checkpoint.
    ///
    /// Evicts the outgoing one FIRST. Both are ~1.6–2.4 GB resident and the governor would
    /// otherwise be asked to hold both for no reason — the user asked to switch, not to
    /// compare side by side. Registration is untouched: both packages stay registered, so
    /// this is a `prepare()` on the other id rather than a re-register.
    ///
    /// Re-enters the same first-run stops as `bootstrap()`, because the second checkpoint's
    /// weights may not be on disk even when the first one's are — `needsDownload` is asked
    /// per package, not once for the app.
    func select(_ next: Audio8Checkpoint) async {
        guard next != checkpoint, !engineState.isBusy else { return }
        if let current = packageID { await engine.evict(package: current) }

        checkpoint = next
        lastError = nil
        // Load-time metrics belong to the model that produced them; carrying the previous
        // checkpoint's numbers across a switch would misattribute them.
        loadSeconds = nil
        pendingLoadSeconds = nil
        residentFloorBytes = 0

        guard storage.resolvedModelsDirectory != nil else {
            engineState = .needsFolder
            return
        }
        if await engine.needsDownload(.tts, package: packageID) {
            engineState = .needsDownload
            return
        }
        await loadModel()
    }

    /// Re-runs the golden path after the user applies a different models folder.
    /// `useModelStore` only affects packages registered AFTER it, so a folder change has
    /// to re-register — otherwise the package keeps its old (or absent) store and keeps
    /// failing with the same message no matter how many times the user retries.
    func storeChangedIfNeeded() async {
        let pathChanged = storage.appliedPath != boundStorePath
        let grantChanged = storage.resolvedModelsDirectory != boundStoreRoot
        guard pathChanged || grantChanged else { return }
        // Evict every registered package, not just the selected one: a folder change
        // invalidates the store for both, and the unselected one may still be resident from
        // before the switch.
        for id in packageIDs.values { await engine.evict(package: id) }
        await bootstrap()
    }

    /// Download (first run) + load, behind the ModelStateView progress strip.
    func loadModel() async {
        // Guard against a load already IN FLIGHT — not against `.registering`. `bootstrap()`
        // hands off to this method while still in `.registering`, so an `isBusy` guard here
        // (which counts `.registering` as busy) silently swallowed the handoff and pinned the
        // app at "Registering" forever. It only reproduced once the weights were already on
        // disk: with a download pending, bootstrap stops at `.needsDownload` and the user
        // re-enters through the button, where the state is no longer busy.
        guard engineState != .preparing, engineState != .working else { return }
        lastError = nil
        engineState = .preparing
        do {
            let start = Date()
            _ = try await engine.prepare(.tts, package: packageID)
            pendingLoadSeconds = Date().timeIntervalSince(start)
            loadSeconds = pendingLoadSeconds

            // Resident floor: post-load, pre-run. Trim through the engine (its documented
            // consumer API) so the floor reflects referenced weights, not load leftovers.
            engine.trimCaches()
            residentFloorBytes = engine.gpuPoolSnapshot()?.activeBytes ?? 0
            GPU.resetPeakMemory()

            engineState = .ready
            storage.refresh()   // disk-used / models-installed reflect new weights
        } catch {
            let message = String(describing: error)
            engineState = .failed(message)
            lastError = message
        }
    }

    func evict() async {
        await engine.evict(.tts, package: packageID)
        engineState = .idle
        residentFloorBytes = 0
        loadSeconds = nil
        storage.refreshStatus()
    }

    // MARK: - Synthesis

    /// Runs one synthesis and appends a measured record. Returns the record (also
    /// appended to `records`) so a sweep can inspect it.
    @discardableResult
    func synthesize(text: String,
                    voice: VoiceSource,
                    referenceAudio: Audio?,
                    referenceTranscript: String?,
                    parameters: RunParameters,
                    promptLabel: String? = nil) async -> RunRecord {
        if engineState != .ready { await loadModel() }

        let before = currentMemory()
        // Per-run transient requires a per-run peak. MLX's peak is a process-lifetime
        // high-water with no engine-side reset, so this is the one place the app reaches
        // past the engine into MLX directly.
        GPU.resetPeakMemory()
        liveFrames = 0
        engineState = .working
        let started = Date()

        var request = TTSRequest(
            text: text,
            voice: referenceAudio.map { VoiceSelector(.referenceAudio($0)) } ?? VoiceSelector(.auto),
            referenceTranscript: referenceTranscript,
            metaData: metaData(from: parameters))

        // Poll the package's own progress reports for a live frame count. The package
        // reports .generate per frame, which doubles as evidence its cancellation
        // checkpoint cadence is real.
        let ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                if let report = self.engine.runProgress.report(for: .tts), let step = report.step {
                    self.liveFrames = step
                }
            }
        }
        defer { ticker.cancel() }

        var failure: String?
        var samples: [Float] = []
        var sampleRate = 44_100
        var frames = 0

        do {
            let response = try await engine.run(request, package: packageID)
            guard let tts = response as? TTSResponse else {
                throw BenchError.unexpectedResponse
            }
            sampleRate = tts.audio.sampleRate ?? 44_100
            samples = Self.decodePCM16(tts.audio.data)
            frames = liveFrames
            lastAudioURL = try? Self.writeTemp(tts.audio.data)
            engineState = .ready
        } catch is CancellationError {
            failure = "Cancelled"
            engineState = .ready
        } catch {
            failure = String(describing: error)
            engineState = .ready
        }

        let runSeconds = Date().timeIntervalSince(started)
        let after = currentMemory()
        let record = RunRecord(
            id: UUID(),
            startedAt: started,
            checkpoint: checkpoint,
            voice: voice,
            promptLabel: promptLabel,
            text: text,
            referenceTranscript: referenceTranscript,
            parameters: parameters,
            loadSeconds: pendingLoadSeconds,
            runSeconds: runSeconds,
            frames: frames,
            sampleCount: samples.count,
            sampleRate: sampleRate,
            rmsDBFS: Self.rmsDBFS(samples),
            peakDBFS: Self.peakDBFS(samples),
            memoryBefore: before,
            memoryAfter: after,
            transientBytes: after.mlxPeakBytes > residentFloorBytes
                ? after.mlxPeakBytes - residentFloorBytes : 0,
            failure: failure)

        pendingLoadSeconds = nil   // a load is charged to exactly one run
        records.append(record)
        return record
    }

    /// Sweep the whole corpus × prompt suite. This is the regression run: fixed voices,
    /// fixed prompts, deterministic decoding, so two builds are directly comparable.
    func runSweep(voices: [ReferenceVoice] = VoiceCorpus.all,
                  prompts: [BenchmarkPrompt] = BenchmarkPrompt.suite,
                  parameters: RunParameters = .deterministic) async {
        for voice in voices {
            guard let url = voice.bundleURL, let audio = try? Self.loadAudio(url) else { continue }
            for prompt in prompts {
                await synthesize(text: prompt.text,
                                 voice: .corpus(id: voice.id),
                                 referenceAudio: audio,
                                 referenceTranscript: voice.transcript,
                                 parameters: parameters,
                                 promptLabel: prompt.label)
            }
        }
    }

    func clearRecords() { records.removeAll() }

    // MARK: - Playback

    func play(url: URL? = nil) {
        guard let target = url ?? lastAudioURL else { return }
        player = try? AVAudioPlayer(contentsOf: target)
        player?.play()
    }

    func stopPlayback() { player?.stop(); player = nil }

    // MARK: - Helpers

    private func metaData(from parameters: RunParameters) -> MetaData {
        var meta: MetaData = [
            "temperature": .double(parameters.temperature),
            "topP": .double(parameters.topP),
            "topK": .int(parameters.topK),
            "maxFrames": .int(parameters.maxFrames),
        ]
        if parameters.greedy { meta["greedy"] = .bool(true) }
        if let seed = parameters.seed { meta["seed"] = .int(seed) }
        return meta
    }

    /// Pool readings come from the ENGINE's telemetry, not a direct MLX import — that is
    /// the documented consumer surface ("pool observability without importing MLX"), and
    /// it reports the same process-global pool. Returns zeros only when MLX has no Metal
    /// device to observe.
    private func currentMemory() -> MemoryReading {
        guard let pool = engine.gpuPoolSnapshot() else {
            return MemoryReading(mlxActiveBytes: 0, mlxCacheBytes: 0, mlxPeakBytes: 0,
                                 physFootprintBytes: Self.physFootprint())
        }
        return MemoryReading(
            mlxActiveBytes: pool.activeBytes,
            mlxCacheBytes: pool.cacheBytes,
            mlxPeakBytes: pool.peakBytes,
            physFootprintBytes: Self.physFootprint())
    }

    static func loadAudio(_ url: URL) throws -> Audio {
        Audio(format: .wav, data: try Data(contentsOf: url), sampleRate: 44_100, channels: 1)
    }

    private static func writeTemp(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio8-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    /// 16-bit PCM WAV → float samples. Skips the 44-byte canonical header.
    static func decodePCM16(_ data: Data) -> [Float] {
        guard data.count > 44 else { return [] }
        let payload = data.dropFirst(44)
        var out = [Float]()
        out.reserveCapacity(payload.count / 2)
        var iterator = payload.makeIterator()
        while let low = iterator.next(), let high = iterator.next() {
            let sample = Int16(bitPattern: UInt16(low) | (UInt16(high) << 8))
            out.append(Float(sample) / 32_767)
        }
        return out
    }

    static func rmsDBFS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -.infinity }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = (sum / Double(samples.count)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -.infinity
    }

    static func peakDBFS(_ samples: [Float]) -> Double {
        guard let peak = samples.map({ Double(abs($0)) }).max(), peak > 0 else { return -.infinity }
        return 20 * log10(peak)
    }

    /// Real process footprint. MLX's own accounting under-reads vs this, so both are
    /// recorded and the UI shows them side by side rather than picking one.
    static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    enum BenchError: Error { case unexpectedResponse }
}

// MARK: - Long-form orchestration (TTSOrchestratorKit)

extension Audio8Bench {

    /// Synthesize one chunk and hand back its WAV bytes. Exists so the orchestrator's
    /// non-isolated closure has a single actor-isolated entry point instead of touching
    /// `lastAudioURL` across the isolation boundary.
    func synthesizeWAV(text: String, voice: VoiceSource, referenceAudio: Audio?,
                       referenceTranscript: String?, parameters: RunParameters) async -> Data {
        let record = await synthesize(
            text: text, voice: voice, referenceAudio: referenceAudio,
            referenceTranscript: referenceTranscript, parameters: parameters,
            promptLabel: "long-form")
        guard record.succeeded, let url = lastAudioURL,
              let data = try? Data(contentsOf: url) else { return Data() }
        return data
    }

    /// One measured long-form render.
    struct LongFormResult: Sendable {
        let chunks: Int
        let totalSeconds: Double
        let audioSeconds: Double
        /// The WORST per-chunk transient — the number that matters, because it is what the
        /// memory envelope actually has to cover.
        let peakTransientBytes: UInt64
        let wavURL: URL?
        var realTimeFactor: Double { audioSeconds > 0 ? totalSeconds / audioSeconds : 0 }
    }

    /// Long-form synthesis via `TTSOrchestratorKit`: split on sentence boundaries to
    /// ~`targetSeconds` segments, synthesize each through the engine, crossfade-assemble.
    ///
    /// This is the ANSWER to two things the corpus sweep measured:
    ///
    ///  1. **The activation transient scales with utterance length** (0.9 s → 1.6 GB,
    ///     15.7 s → 6.35 GB), so a whole-article one-shot render is unbounded. Chunking caps
    ///     every decode at the chunk target, which is what makes the declared
    ///     `peakActivationBytes` a real ceiling instead of a guess about input length.
    ///  2. **Short utterances run SLOWER than realtime** (RTF 1.05–1.64 at ~0.9 s, vs
    ///     0.85–0.94 above 5 s) because fixed per-request cost dominates. The chunker MERGES
    ///     short sentences toward the target, so orchestration also avoids that regime —
    ///     the merge is a throughput decision, not only a seam-quality one.
    ///
    /// Voice consistency uses `.anchorToFirstSegment`: chunk 0 renders from the chosen
    /// reference, then its audio + text become the reference for every later chunk, so the
    /// voice cannot drift across a long passage.
    func runLongForm(text: String,
                     voice: VoiceSource,
                     referenceAudio: Audio?,
                     referenceTranscript: String?,
                     targetSeconds: Double = 15,
                     parameters: RunParameters = .spaceDefaults) async -> LongFormResult? {
        if engineState != .ready { await loadModel() }
        let started = Date()
        let baseline = records.count

        let chunker = TextChunker(options: .init(targetSeconds: targetSeconds))
        let orchestrator = LongFormTTS(
            chunker: chunker,
            polish: .broadcast,
            consistency: .anchorToFirstSegment
        ) { [weak self] chunk, reference in
            guard let self else { return Data() }
            // The orchestrator hands back chunk 0's audio as the reference for later chunks;
            // realize that as this model's cloning path so the voice stays fixed.
            let audio: Audio?
            let transcript: String?
            if let reference {
                audio = Audio(format: .wav, data: reference.wav, sampleRate: 44_100, channels: 1)
                transcript = reference.transcript
            } else {
                audio = referenceAudio
                transcript = referenceTranscript
            }
            // The orchestrator's closure is non-isolated; hop back to the actor that owns
            // the engine rather than reaching at its state from here.
            return await self.synthesizeWAV(
                text: chunk, voice: voice, referenceAudio: audio,
                referenceTranscript: transcript, parameters: parameters)
        }

        do {
            let wav = try await orchestrator.generate(text)
            let produced = Array(records.dropFirst(baseline))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("audio8-longform-\(UUID().uuidString).wav")
            try? wav.write(to: url)
            lastAudioURL = url
            return LongFormResult(
                chunks: produced.count,
                totalSeconds: Date().timeIntervalSince(started),
                audioSeconds: produced.reduce(0) { $0 + $1.duration },
                peakTransientBytes: produced.map(\.transientBytes).max() ?? 0,
                wavURL: url)
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }
}
