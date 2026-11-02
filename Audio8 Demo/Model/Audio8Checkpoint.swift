//  Which Audio8 checkpoint a run used.
//
//  Three checkpoints share an architecture family, a codec, and this app's entire request
//  path — but are separate `ModelPackage`s because their manifests genuinely differ (licence,
//  footprint, provenance, surface, languages). The engine supports several packages behind
//  one capability, selected by `PackageID`, so this app registers ALL of them and routes
//  `prepare`/`run`/`evict` at whichever is selected. Realistic-0.6b is the default since
//  mlx-audio8-tts-swift v0.4.0; the Preview-0.6b stays for its shorter pauses.
//
//  Every `RunRecord` carries the checkpoint that produced it. That is the point of having
//  both here: a metrics harness that cannot say which model produced a number is measuring
//  the app, not the models.

import Foundation
import MLXAudio8TTS
import MLXToolKit

enum Audio8Checkpoint: String, CaseIterable, Identifiable, Codable, Sendable {
    case realistic06b
    case preview06b
    case preview01b

    var id: String { rawValue }

    /// Short label for pickers and table columns — kept tight because it appears per row.
    var shortName: String {
        switch self {
        case .realistic06b: "0.6B Realistic"
        case .preview06b: "0.6B Preview"
        case .preview01b: "0.1B"
        }
    }

    var displayName: String {
        switch self {
        case .realistic06b: "Audio8-TTS-Realistic-0.6b"
        case .preview06b: "Audio8-TTS-Preview-0.6b"
        case .preview01b: "Audio8-TTS-Preview-0.1b"
        }
    }

    /// One line of honest guidance, shown next to the picker. The 0.1b's case is footprint;
    /// saying so plainly is more useful than letting "newer/smaller" read as "better". The
    /// Preview-0.6b's case is pacing: it ties Realistic on accuracy and similarity in the
    /// languages both cover, but pauses less (Realistic's takes run ~13% longer, all silence).
    var subtitle: String {
        switch self {
        case .realistic06b:
            "601M LM · 17 languages · default; more natural pauses, takes ~13% longer"
        case .preview06b:
            "601M LM · 11 languages · same quality, shorter pauses for tight timing"
        case .preview01b:
            "170M LM · 8 languages · smaller download, lower similarity"
        }
    }

    /// Approximate first-run download, for the consent prompt. Both include the SAME 1.35 GB
    /// codec — which is why the smaller model is not proportionally smaller on disk.
    var approximateDownloadDescription: String {
        switch self {
        case .realistic06b: "~2.6 GB"
        case .preview06b: "~2.6 GB"
        case .preview01b: "~1.7 GB"
        }
    }

    /// What the manifest declares it needs resident, post-load. Surfaced in the UI because
    /// the interesting fact is how LITTLE the smaller model saves: the shared codec is most
    /// of the floor either way.
    var declaredResidentBytes: UInt64 {
        switch self {
        case .realistic06b: Audio8RealisticPackage.manifest.residentBytesForBF16
        case .preview06b: Audio8Package.manifest.residentBytesForBF16
        case .preview01b: Audio8MiniPackage.manifest.residentBytesForBF16
        }
    }

    /// The package's manifest, for anything that reads a declared number. One switch here
    /// keeps the UI from hardcoding a single package's declaration.
    var manifest: PackageManifest {
        switch self {
        case .realistic06b: Audio8RealisticPackage.manifest
        case .preview06b: Audio8Package.manifest
        case .preview01b: Audio8MiniPackage.manifest
        }
    }

    /// The weights repo, shown in Settings so the user can see what will be fetched.
    var repo: String {
        switch self {
        case .realistic06b: Audio8RealisticConfiguration().repo
        case .preview06b: Audio8Configuration().repo
        case .preview01b: Audio8MiniConfiguration().repo
        }
    }
}

extension PackageManifest {
    /// The declared bf16 resident floor, or 0 if the package declares no bf16 footprint.
    /// Read from the manifest rather than restated in the UI — a second copy of a measured
    /// number is a second copy to get wrong.
    var residentBytesForBF16: UInt64 {
        requirements.footprints.first { $0.quant == .bf16 }?.residentBytes ?? 0
    }
}
