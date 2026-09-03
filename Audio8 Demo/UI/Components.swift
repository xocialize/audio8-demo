//  Components.swift
//  What is left after DesignScaffold. Every value comes from `Tokens`; every shape that
//  the fleet shares comes from the package. What remains here is Audio8's own vocabulary:
//  a panel container, a level verdict, a parameter slider, and the engine-state mapping.
//
//  Deleted from this file when the components landed (AB-A-0034 follow-through):
//    · `MetricTile`      → DesignScaffoldMetrics. The package's tile IS this one — Audio8's
//                          copy was the donor of the four it was promoted from.
//    · `EngineStatusPill` → still here, but as ~10 lines over DesignScaffoldStatus.StatusPill
//                          rather than a hand-drawn capsule. The app keeps the LABEL and the
//                          state mapping, which is app vocabulary; the pill is not.
//    · `Section`         → `LabeledSection`, and its header is now `SectionHeader`.
//    · `ParameterSlider` → DesignScaffoldControls.LabeledSlider. It was one of SEVEN on
//                          the volume, and one of the two whose Int bridge truncated.

import DesignScaffold
import DesignScaffoldControls
import DesignScaffoldMetrics
import DesignScaffoldStatus
import SwiftUI

/// A titled group: an icon, a title, and content beneath.
///
/// Renamed from `Section`, which shadowed `SwiftUI.Section` for every file in the target —
/// a top-level type with that name means `Section { }` inside a `Form` or `List` silently
/// resolves to this instead, and the failure looks like a layout bug rather than a name
/// collision.
///
/// ## Why the header is themed rather than adopting the house style verbatim
///
/// `SectionHeader`'s default is the fleet's eyebrow: 11pt uppercase, `secondaryLabel`. This
/// app's panels are settings-style groups with a leading SF Symbol, where an 11pt uppercase
/// label sits badly next to a 13pt icon. So the *component* is adopted — which is what brings
/// the tracking, the `.isHeader` accessibility trait, and future fixes — and the *look* is
/// declared as a theme instead of being redrawn. Deleting `.theme(Self.header)` below is the
/// entire change needed to fall back to the house style.
///
/// The leading icon is deliberately NOT in the package: a fleet sweep found no second app that
/// wanted one, and one need is not a promotion (AB-D-0049).
struct LabeledSection<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    private static var header: SectionHeaderTheme {
        SectionHeaderTheme(font: Tokens.Font.sectionTitle,
                           color: Tokens.Color.label,
                           tracking: 0,
                           uppercases: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Tokens.Color.secondaryLabel)
                }
                SectionHeader(title).theme(Self.header)
            }
            content
        }
    }
}

/// Engine status pill — the app's single source of "what is the engine doing right now".
///
/// The pill itself is `DesignScaffoldStatus.StatusPill`. What stays here is what the package
/// deliberately does not own: the LABEL, and the mapping from this app's seven-case engine
/// state onto the four states a status pill reports.
struct EngineStatusPill: View {
    let state: Audio8Bench.EngineState

    var body: some View {
        StatusPill(state.label, status: state.status)
            // `.failed(why)` composes a sentence, and the sidebar is 260pt wide. The full
            // text is already rendered beneath as `bench.lastError`.
            .lineLimit(1)
    }
}

extension Audio8Bench.EngineState {
    /// What the pill reports.
    ///
    /// `needsFolder` and `needsDownload` are `.attention`: settled, amber, waiting on the
    /// user, not usable until they act. Until DesignScaffold 0.23.0 they were mapped to
    /// `.working()` — the only amber case that existed — which made a state that was
    /// waiting on the USER pulse "hold on" at them indefinitely. This app's compromise was
    /// one of the three needs that promoted the case (AB-A-0060).
    var status: Status {
        switch self {
        case .ready: .ready
        case .failed: .failed
        case .idle: .idle
        case .needsFolder, .needsDownload: .attention
        case .registering, .preparing, .working: .working()
        }
    }
}

/// Level meter that states the verdict in words as well as color — a silent render is
/// the failure this app exists to surface, so it should never be a subtle cue.
///
/// NOT `DesignScaffoldWaveform.AudioLevelMeter`, and the difference is real rather than
/// stylistic: that one draws a live bar meter of a signal in flight, this one renders a
/// settled verdict about a finished render. Substituting it would lose the word.
struct LevelIndicator: View {
    let rmsDBFS: Double
    let peakDBFS: Double
    let level: RunRecord.Level

    private var tint: Color {
        switch level {
        case .silent: Tokens.Color.levelSilent
        case .low: Tokens.Color.levelLow
        case .healthy: Tokens.Color.levelHealthy
        case .clipping: Tokens.Color.levelSilent
        }
    }

    private var verdict: String {
        switch level {
        case .silent: "SILENT"
        case .low: "Low"
        case .healthy: "OK"
        case .clipping: "CLIPPING"
        }
    }

    private func fmt(_ value: Double) -> String {
        value.isFinite ? String(format: "%.1f", value) : "−∞"
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Text(verdict)
                .font(Tokens.Font.metricLabel)
                .foregroundStyle(tint)
            Text("rms \(fmt(rmsDBFS)) · peak \(fmt(peakDBFS)) dBFS")
                .font(Tokens.Font.metricInline)
                .foregroundStyle(Tokens.Color.secondaryLabel)
        }
    }
}

extension Double {
    /// Bytes → MB/GB, chosen by magnitude so tables stay readable.
    static func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
