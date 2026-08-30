//  SynthesizeView.swift
//  The synthesis surface — modeled on the Audio8 HF Space's controls, adapted to a
//  native macOS inspector layout.
//
//  Deviation from the Space, on purpose: the Space hardcodes one set of sampling
//  defaults (0.8 / 0.95 / 1024) that differ from the model card's (0.7 / 0.9 / 512).
//  Rather than pick a winner silently, both presets are offered plus a deterministic
//  preset — because "which defaults are actually better" is a question this app exists
//  to answer with measurements.

import DesignScaffold
import MLXToolKit
import SwiftUI
import UniformTypeIdentifiers

struct SynthesizeView: View {
    @Bindable var bench: Audio8Bench

    @State private var text: String = BenchmarkPrompt.suite[1].text
    @State private var selectedVoiceID: String = VoiceCorpus.all.first?.id ?? "clara"
    @State private var customAudioURL: URL?
    @State private var customTranscript: String = ""
    @State private var parameters: RunParameters = .spaceDefaults
    @State private var isImporting = false

    private var usingCustomVoice: Bool { customAudioURL != nil }

    private var activeVoice: ReferenceVoice? { VoiceCorpus.voice(id: selectedVoiceID) }

    private var characterCount: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).count }

    private var validationError: String? {
        if characterCount == 0 { return "Text must not be empty" }
        if characterCount > RunParameters.maxCharacters {
            return "Text must be \(RunParameters.maxCharacters) characters or fewer"
        }
        if usingCustomVoice && customTranscript.trimmingCharacters(in: .whitespaces).isEmpty {
            return "A custom reference clip needs its transcript — the model conditions on the pair"
        }
        return nil
    }

    var body: some View {
        HSplitView {
            composer
                .frame(minWidth: 460)
            inspector
                .frame(minWidth: Tokens.Layout.inspectorWidth,
                       idealWidth: Tokens.Layout.inspectorWidth,
                       maxWidth: Tokens.Layout.inspectorMaxWidth)
        }
    }

    // MARK: Composer

    private var composer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                LabeledSection(title: "Text", systemImage: Tokens.Symbol.generate) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        TextEditor(text: $text)
                            .font(Tokens.Font.body)
                            .frame(minHeight: 120)
                            .padding(Tokens.Space.s)
                            .cardSurface()
                        HStack {
                            ForEach(BenchmarkPrompt.suite) { prompt in
                                Button(prompt.label) { text = prompt.text }
                                    .buttonStyle(.link)
                                    .font(Tokens.Font.caption)
                            }
                            Spacer()
                            Text("\(characterCount)/\(RunParameters.maxCharacters)")
                                .font(Tokens.Font.metricInline)
                                .foregroundStyle(characterCount > RunParameters.maxCharacters
                                                 ? Tokens.Color.failure : Tokens.Color.secondaryLabel)
                        }
                    }
                }

                LabeledSection(title: "Reference voice", systemImage: Tokens.Symbol.voice) {
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Tokens.Space.s)],
                                  spacing: Tokens.Space.s) {
                            ForEach(VoiceCorpus.all) { voice in
                                VoiceChip(voice: voice,
                                          isSelected: !usingCustomVoice && voice.id == selectedVoiceID,
                                          onSelect: {
                                              customAudioURL = nil
                                              selectedVoiceID = voice.id
                                          },
                                          onPreview: { bench.play(url: voice.bundleURL) })
                            }
                        }

                        HStack(spacing: Tokens.Space.s) {
                            Button {
                                isImporting = true
                            } label: {
                                Label(usingCustomVoice
                                      ? (customAudioURL?.lastPathComponent ?? "Custom clip")
                                      : "Use your own clip…",
                                      systemImage: Tokens.Symbol.upload)
                            }
                            if usingCustomVoice {
                                Button("Clear") { customAudioURL = nil; customTranscript = "" }
                                    .buttonStyle(.link)
                            }
                        }

                        if usingCustomVoice {
                            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                Text("Transcript of the clip")
                                    .font(Tokens.Font.caption)
                                    .foregroundStyle(Tokens.Color.secondaryLabel)
                                TextField("Exactly what the clip says", text: $customTranscript)
                                    .textFieldStyle(.roundedBorder)
                                    .font(Tokens.Font.body)
                                Text("Audio8 clones in-context: the transcript must match the audio.")
                                    .font(Tokens.Font.caption)
                                    .foregroundStyle(Tokens.Color.tertiaryLabel)
                            }
                        }
                    }
                }

                if let record = bench.records.last {
                    LabeledSection(title: "Last render", systemImage: Tokens.Symbol.metrics) {
                        VStack(alignment: .leading, spacing: Tokens.Space.s) {
                            LevelIndicator(rmsDBFS: record.rmsDBFS,
                                           peakDBFS: record.peakDBFS,
                                           level: record.level)
                            HStack(spacing: Tokens.Space.s) {
                                Button {
                                    bench.play()
                                } label: { Label("Play", systemImage: Tokens.Symbol.play) }
                                    .disabled(bench.lastAudioURL == nil)
                                Button {
                                    bench.stopPlayback()
                                } label: { Label("Stop", systemImage: Tokens.Symbol.stop) }
                                Button {
                                    save(record)
                                } label: { Label("Save…", systemImage: Tokens.Symbol.save) }
                                    .disabled(bench.lastAudioURL == nil)
                            }
                        }
                        .padding(Tokens.Space.m)
                        .cardSurface()
                    }
                }
            }
            .padding(Tokens.Space.xl)
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.wav, .mp3, .mpeg4Audio, .aiff, .audio]) { result in
            if case .success(let url) = result { customAudioURL = url }
        }
    }

    // MARK: Inspector

    private var inspector: some View {
        ScrollView {
            // `maxWidth: .infinity` + clipping keeps ONE over-wide child from widening the
            // column and pushing its siblings out of view, which is what happened here.
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                LabeledSection(title: "Sampling", systemImage: Tokens.Symbol.settings) {
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        // A .segmented picker takes its IDEAL width and refuses to compress.
                        // With four descriptive labels that is ~400 pt, which forced this whole
                        // VStack wider than the inspector and clipped every sibling on both
                        // edges. A menu picker keeps the labels readable and imposes no width.
                        Picker("Preset", selection: presetBinding) {
                            Text("Space defaults").tag(0)
                            Text("Model card").tag(1)
                            Text("Deterministic").tag(2)
                            Text("Custom").tag(3)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ParameterSlider(title: "Temperature", value: $parameters.temperature,
                                        range: RunParameters.temperatureRange,
                                        help: "Higher is more varied. The Space defaults to 0.8; "
                                            + "the model card to 0.7.")
                        ParameterSlider(title: "Top P", value: $parameters.topP,
                                        range: RunParameters.topPRange)
                        ParameterSlider(title: "Top K",
                                        value: Binding(
                                            get: { Double(parameters.topK) },
                                            set: { parameters.topK = Int($0) }),
                                        range: RunParameters.topKSliderRange,
                                        step: 1, format: "%.0f")
                        ParameterSlider(title: "Max frames",
                                        value: Binding(
                                            get: { Double(parameters.maxFrames) },
                                            set: { parameters.maxFrames = Int($0) }),
                                        range: RunParameters.maxFramesSliderRange,
                                        step: 32, format: "%.0f",
                                        help: "One frame ≈ 46 ms of audio.")

                        Toggle("Greedy (deterministic)", isOn: $parameters.greedy)
                            .font(Tokens.Font.caption)
                            .help("Argmax decoding — the configuration proven token-exact against "
                                  + "the PyTorch reference. Use for regression comparison.")

                        HStack {
                            Toggle("Seed", isOn: seedEnabled)
                                .font(Tokens.Font.caption)
                            if parameters.seed != nil {
                                TextField("", value: Binding(
                                    get: { parameters.seed ?? 0 },
                                    set: { parameters.seed = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                    .font(Tokens.Font.metricInline)
                            }
                        }

                        Text("≈ \(String(format: "%.1f", Double(parameters.maxFrames) * 0.0464)) s ceiling")
                            .font(Tokens.Font.caption)
                            .foregroundStyle(Tokens.Color.tertiaryLabel)
                    }
                    .padding(Tokens.Space.m)
                    .cardSurface()
                }

                if let validationError {
                    Text(validationError)
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.failure)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await generate() }
                } label: {
                    Label(bench.engineState == .working ? "Generating…" : "Generate",
                          systemImage: Tokens.Symbol.generate)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(validationError != nil || bench.engineState.isBusy)

                if bench.engineState == .working {
                    HStack(spacing: Tokens.Space.s) {
                        ProgressView().controlSize(.small)
                        Text("\(bench.liveFrames) frames")
                            .font(Tokens.Font.metricInline)
                            .foregroundStyle(Tokens.Color.secondaryLabel)
                    }
                }

                LiveMetricsPanel(bench: bench)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Space.l)
        }
        .clipped()
    }

    // MARK: Bindings

    private var seedEnabled: Binding<Bool> {
        Binding(get: { parameters.seed != nil },
                set: { parameters.seed = $0 ? 1234 : nil })
    }

    /// Maps the preset picker onto the parameter set, reporting "Custom" whenever the
    /// values no longer match a known preset.
    private var presetBinding: Binding<Int> {
        Binding(
            get: {
                switch parameters {
                case .spaceDefaults: 0
                case .modelCardDefaults: 1
                case .deterministic: 2
                default: 3
                }
            },
            set: { selection in
                switch selection {
                case 0: parameters = .spaceDefaults
                case 1: parameters = .modelCardDefaults
                case 2: parameters = .deterministic
                default: break
                }
            })
    }

    // MARK: Actions

    private func generate() async {
        let voiceSource: VoiceSource
        var audio: Audio?
        var transcript: String?

        if let customAudioURL {
            let scoped = customAudioURL.startAccessingSecurityScopedResource()
            defer { if scoped { customAudioURL.stopAccessingSecurityScopedResource() } }
            audio = try? Audio8Bench.loadAudio(customAudioURL)
            transcript = customTranscript
            voiceSource = .custom(filename: customAudioURL.lastPathComponent)
        } else if let voice = activeVoice, let url = voice.bundleURL {
            audio = try? Audio8Bench.loadAudio(url)
            transcript = voice.transcript
            voiceSource = .corpus(id: voice.id)
        } else {
            voiceSource = .defaultVoice
        }

        let label = BenchmarkPrompt.suite.first { $0.text == text }?.label
        await bench.synthesize(text: text,
                               voice: voiceSource,
                               referenceAudio: audio,
                               referenceTranscript: transcript,
                               parameters: parameters,
                               promptLabel: label)
    }

    private func save(_ record: RunRecord) {
        guard let source = bench.lastAudioURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "audio8-\(record.voice.label)-\(Int(record.startedAt.timeIntervalSince1970)).wav"
        if panel.runModal() == .OK, let destination = panel.url {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: source, to: destination)
        }
    }
}

/// One selectable corpus voice, with an inline preview so the reference can be heard
/// before it conditions a render.
private struct VoiceChip: View {
    let voice: ReferenceVoice
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Tokens.Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(voice.name)
                        .font(Tokens.Font.body)
                        .foregroundStyle(Tokens.Color.label)
                    Text("\(voice.locale) · \(voice.tone)")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: onPreview) {
                    Image(systemName: Tokens.Symbol.play)
                        .font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .help("Preview the reference clip")
            }
            .padding(Tokens.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Tokens.Color.accent.opacity(0.14) : Tokens.Color.surface,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.control)
                    .strokeBorder(isSelected ? Tokens.Color.accent : Tokens.Color.separator,
                                  lineWidth: Tokens.Layout.hairline))
        }
        .buttonStyle(.plain)
    }
}
