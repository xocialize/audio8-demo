//  LongFormView.swift
//  Long-form orchestration via TTSOrchestratorKit, and the A/B that justifies it.
//
//  The corpus sweep established two things about this model: the activation transient grows
//  with utterance length (0.9 s → 1.6 GB, 15.7 s → 6.35 GB), and short utterances run
//  SLOWER than realtime because fixed per-request cost dominates. Chunking addresses both,
//  so this pane exists to MEASURE that rather than assert it: run the same passage one-shot
//  and orchestrated, and compare peak transient and RTF side by side.

import DesignScaffold
import DesignScaffoldControls
import SwiftUI

struct LongFormView: View {
    @Bindable var bench: Audio8Bench

    @State private var text = LongFormView.sample
    @State private var targetSeconds: Double = 15
    @State private var selectedVoiceID = VoiceCorpus.all.first?.id ?? "clara"
    @State private var isRunning = false
    @State private var orchestrated: Audio8Bench.LongFormResult?
    @State private var oneShot: RunRecord?

    private var voice: ReferenceVoice? { VoiceCorpus.voice(id: selectedVoiceID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                Text("Splits on sentence boundaries to ~target-second segments, synthesizes each "
                     + "through the engine, and crossfade-assembles them. Voice is anchored to the "
                     + "first segment so it cannot drift across the passage.")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledSection(title: "Passage", systemImage: Tokens.Symbol.generate) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        TextEditor(text: $text)
                            .font(Tokens.Font.body)
                            .frame(minHeight: 140)
                            .padding(Tokens.Space.s)
                            .cardSurface()
                        Text("\(text.count) characters · ~\(Int(Double(text.count) / 15)) s estimated")
                            .font(Tokens.Font.caption)
                            .foregroundStyle(Tokens.Color.tertiaryLabel)
                    }
                }

                LabeledSection(title: "Settings", systemImage: Tokens.Symbol.settings) {
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Picker("Voice", selection: $selectedVoiceID) {
                            ForEach(VoiceCorpus.all) { v in
                                Text("\(v.name) · \(v.locale)").tag(v.id)
                            }
                        }
                        .frame(maxWidth: 320)
                        LabeledSlider("Chunk target", value: $targetSeconds, in: 5...30,
                                      decimals: 0, unit: " s")
                            .help("Caps every decode. Larger means fewer seams but a "
                                  + "bigger activation peak per chunk.")
                            .frame(maxWidth: 320)
                    }
                    .padding(Tokens.Space.m)
                    .cardSurface()
                }

                HStack(spacing: Tokens.Space.m) {
                    Button {
                        Task { await runOrchestrated() }
                    } label: {
                        Label(isRunning ? "Running…" : "Run orchestrated",
                              systemImage: Tokens.Symbol.benchmark)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || bench.engineState.isBusy)

                    Button {
                        Task { await runOneShot() }
                    } label: { Label("Run one-shot (compare)", systemImage: Tokens.Symbol.generate) }
                        .disabled(isRunning || bench.engineState.isBusy)
                        .help("Synthesize the whole passage as a single utterance, for the "
                              + "memory/throughput comparison. May be capped by max frames.")

                    if bench.lastAudioURL != nil {
                        Button { bench.play() } label: {
                            Label("Play", systemImage: Tokens.Symbol.play)
                        }
                    }
                    if isRunning { ProgressView().controlSize(.small) }
                }

                if orchestrated != nil || oneShot != nil { comparison }
            }
            .padding(Tokens.Space.xl)
        }
    }

    private var comparison: some View {
        LabeledSection(title: "Orchestrated vs one-shot", systemImage: Tokens.Symbol.metrics) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                HStack(spacing: Tokens.Space.l) {
                    column(title: "Orchestrated",
                           chunks: orchestrated.map { "\($0.chunks)" } ?? "—",
                           audio: orchestrated.map { String(format: "%.1f s", $0.audioSeconds) } ?? "—",
                           rtf: orchestrated.map { String(format: "%.2f", $0.realTimeFactor) } ?? "—",
                           peak: orchestrated.map { Double.formatBytes($0.peakTransientBytes) } ?? "—")
                    column(title: "One-shot",
                           chunks: oneShot == nil ? "—" : "1",
                           audio: oneShot.map { String(format: "%.1f s", $0.duration) } ?? "—",
                           rtf: oneShot.map { String(format: "%.2f", $0.realTimeFactor) } ?? "—",
                           peak: oneShot.map { Double.formatBytes($0.transientBytes) } ?? "—")
                }

                if let orchestrated, let oneShot, oneShot.transientBytes > 0 {
                    let saved = Double(oneShot.transientBytes) - Double(orchestrated.peakTransientBytes)
                    if saved > 0 {
                        Text(String(format: "Chunking cut the peak activation by %.0f MB (%.0f%%). "
                                    + "More importantly it BOUNDS it: the one-shot figure grows "
                                    + "with passage length, the chunked one does not.",
                                    saved / 1_048_576,
                                    100 * saved / Double(oneShot.transientBytes)))
                            .font(Tokens.Font.caption)
                            .foregroundStyle(Tokens.Color.ready)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Tokens.Space.m)
            .cardSurface()
        }
    }

    private func column(title: String, chunks: String, audio: String,
                        rtf: String, peak: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(title.uppercased())
                .font(Tokens.Font.metricLabel)
                .foregroundStyle(Tokens.Color.secondaryLabel)
            LabeledContent("Segments", value: chunks)
            LabeledContent("Audio", value: audio)
            LabeledContent("RTF", value: rtf)
            LabeledContent("Peak transient", value: peak)
        }
        .font(Tokens.Font.metricInline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func runOrchestrated() async {
        guard let voice, let url = voice.bundleURL,
              let audio = try? Audio8Bench.loadAudio(url) else { return }
        isRunning = true
        defer { isRunning = false }
        orchestrated = await bench.runLongForm(
            text: text, voice: .corpus(id: voice.id), referenceAudio: audio,
            referenceTranscript: voice.transcript, targetSeconds: targetSeconds)
    }

    private func runOneShot() async {
        guard let voice, let url = voice.bundleURL,
              let audio = try? Audio8Bench.loadAudio(url) else { return }
        isRunning = true
        defer { isRunning = false }
        // maxFrames raised so the whole passage fits in one utterance where possible —
        // the point of the comparison is the unbounded decode, so capping it would hide it.
        var params = RunParameters.spaceDefaults
        params.maxFrames = RunParameters.maxFramesRange.upperBound
        oneShot = await bench.synthesize(
            text: text, voice: .corpus(id: voice.id), referenceAudio: audio,
            referenceTranscript: voice.transcript, parameters: params,
            promptLabel: "one-shot")
    }

    /// Long enough to need several segments at any sensible target.
    static let sample = """
        The port began as a question about whether a model published yesterday had reached \
        Apple Silicon yet. It had not, so the work started from the reference implementation \
        and moved outward: first a Python translation checked layer by layer against captured \
        goldens, then a Swift translation checked against the same fixtures, and finally a \
        package the engine could load, admit, and evict on its own terms. Each stage was gated \
        by measurement rather than by inspection, because the failures in this domain are quiet \
        ones. A tensor that is silently transposed still produces audio. A checkpoint loaded \
        with the wrong normalisation still produces audio. The only reliable way to know that a \
        port is correct is to compare it, number by number, against something that already was.
        """
}
