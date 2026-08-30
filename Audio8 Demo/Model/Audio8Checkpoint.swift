//  Which Audio8 checkpoint a run used.
//
//  Audio8 publishes two preview checkpoints that share an architecture family, a codec, and
//  this app's entire request path — but are separate `ModelPackage`s because their manifests
//  genuinely differ (licence, footprint, provenance, surface). The engine supports several
//  packages behind one capability, selected by `PackageID`, so this app registers BOTH and
//  routes `prepare`/`run`/`evict` at whichever is selected.
//
//  Every `RunRecord` carries the checkpoint that produced it. That is the point of having
//  both here: a metrics harness that cannot say which model produced a number is measuring
//  the app, not the models.

import Foundation
import MLXAudio8TTS
import MLXToolKit

enum Audio8Checkpoint: String, CaseIterable, Identifiable, Codable, Sendable {
    case preview06b
    case preview01b

    var id: String { rawValue }

    /// Short label for pickers and table columns — kept tight because it appears per row.
    var shortName: String {
        switch self {
        case .preview06b: "0.6B"
        case .preview01b: "0.1B"
        }
    }

    var displayName: String {
        switch self {
        case .preview06b: "Audio8-TTS-Preview-0.6b"
        case .preview01b: "Audio8-TTS-Preview-0.1b"
        }
    }

    /// One line of honest guidance, shown next to the picker. The 0.1b's case is footprint;
    /// saying so plainly is more useful than letting "newer/smaller" read as "better".
    var subtitle: String {
        switch self {
        case .preview06b:
            "601M LM · 11 languages · higher speaker similarity"
        case .preview01b:
            "170M LM · 8 languages · smaller download, lower similarity"
        }
    }

    /// Approximate first-run download, for the consent prompt. Both include the SAME 1.35 GB
    /// codec — which is why the smaller model is not proportionally smaller on disk.
    var approximateDownloadDescription: String {
        switch self {
        case .preview06b: "~2.6 GB"
        case .preview01b: "~1.7 GB"
        }
    }

    /// What the manifest declares it needs resident, post-load. Surfaced in the UI because
    /// the interesting fact is how LITTLE the smaller model saves: the shared codec is most
    /// of the floor either way.
    var declaredResidentBytes: UInt64 {
        switch self {
        case .preview06b: Audio8Package.manifest.residentBytesForBF16
        case .preview01b: Audio8MiniPackage.manifest.residentBytesForBF16
        }
    }

    /// The weights repo, shown in Settings so the user can see what will be fetched.
    var repo: String {
        switch self {
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
