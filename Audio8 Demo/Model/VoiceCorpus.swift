//  VoiceCorpus.swift
//  The fixed reference-voice corpus, mirrored from the Audio8 HF Space
//  (Audio8/Audio8-TTS-Preview-0.6b-SGLang, app.py EXAMPLES).
//
//  WHY A FIXED CORPUS: comparing runs across builds only means something if the
//  conditioning is identical. These six clips + their exact transcripts are the
//  controlled variable. All six ship at 44.1 kHz mono — the codec's native rate — so
//  the resampler is not in the measurement path for corpus voices (a custom upload at
//  another rate WILL exercise it, which is itself worth measuring separately).

import Foundation

struct ReferenceVoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Language as the Space labels it (mixed English/Chinese strings, kept verbatim).
    let locale: String
    /// Voice character as the Space labels it.
    let tone: String
    /// Bundled resource basename (no extension).
    let resource: String
    /// The transcript of what the clip says. Audio8 is an ICL cloner: this must match the
    /// audio or cloning quality degrades — it is conditioning, not metadata.
    let transcript: String

    var bundleURL: URL? {
        Bundle.main.url(forResource: resource, withExtension: "wav", subdirectory: "Voices")
            ?? Bundle.main.url(forResource: resource, withExtension: "wav")
    }
}

enum VoiceCorpus {
    /// Shared transcripts — the Space uses one per language across its examples.
    /// Reproduced verbatim, including the typo in the English line ("todat"), because the
    /// transcript must match the recording rather than be correct prose.
    static let englishTranscript = "hello nice to meet you, what would you like to talk about todat"
    static let chineseTranscript = "你好，我是小周，很高兴认识你"

    static let all: [ReferenceVoice] = [
        ReferenceVoice(id: "clara", name: "Clara", locale: "English", tone: "Female",
                       resource: "en_female_clara", transcript: englishTranscript),
        ReferenceVoice(id: "iris", name: "Iris", locale: "English", tone: "Female",
                       resource: "en_female_iris", transcript: englishTranscript),
        ReferenceVoice(id: "arthur", name: "Arthur", locale: "English", tone: "Male",
                       resource: "en_male_arthur", transcript: englishTranscript),
        ReferenceVoice(id: "mia", name: "Mia", locale: "中文", tone: "女声",
                       resource: "zh_female_mia", transcript: chineseTranscript),
        ReferenceVoice(id: "ben", name: "Ben", locale: "中文", tone: "男声",
                       resource: "zh_male_ben", transcript: chineseTranscript),
        ReferenceVoice(id: "sophie", name: "Sophie", locale: "中英双语", tone: "女声",
                       resource: "zh_en_female_sophie", transcript: chineseTranscript),
    ]

    static func voice(id: String) -> ReferenceVoice? { all.first { $0.id == id } }
}

/// A prompt the benchmark sweep runs against every voice. Short/medium/long matter
/// because the codec's decode transient scales with utterance length — the app should
/// make that slope visible rather than report one number.
struct BenchmarkPrompt: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let text: String

    static let suite: [BenchmarkPrompt] = [
        BenchmarkPrompt(id: "short", label: "Short",
                        text: "Good morning."),
        BenchmarkPrompt(id: "medium", label: "Medium",
                        text: "The quick brown fox jumps over the lazy dog, "
                            + "while the river keeps flowing north."),
        BenchmarkPrompt(id: "long", label: "Long",
                        text: "This is a deliberately longer passage used to measure how the "
                            + "decoder's memory transient scales with utterance length, since the "
                            + "codec decodes a whole utterance through its convolution stack in a "
                            + "single pass rather than streaming it."),
    ]
}
